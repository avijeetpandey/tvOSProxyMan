import Foundation
import Network
import os.log

final class MITMConnection {
    private let clientConn: NWConnection
    private let targetHost: String
    private let targetPort: Int
    private unowned let server: ProxyServer

    private var originConn: NWConnection?
    private var requestBuffer = Data()
    private var networkQueue: DispatchQueue?

    private let logger = Logger(subsystem: "com.tvOSProxyMan", category: "MITMConnection")

    init(decryptedConn: NWConnection,
         targetHost: String, targetPort: Int,
         server: ProxyServer) {
        self.clientConn  = decryptedConn
        self.targetHost  = targetHost
        self.targetPort  = targetPort
        self.server      = server
    }

    func start(on queue: DispatchQueue) {
        networkQueue = queue
        clientConn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:    self.readRequestHead()
            case .failed, .cancelled: self.cancel()
            default: break
            }
        }
        clientConn.start(queue: queue)
    }

    func cancel() {
        clientConn.cancel()
        originConn?.cancel()
    }

    // MARK: - Read decrypted HTTP request head

    private func readRequestHead() {
        clientConn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.logger.debug("MITM read: \(error)"); self.cancel(); return }
            if let data { self.requestBuffer.append(data) }

            let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
            if let range = self.requestBuffer.range(of: terminator) {
                let headersData = Data(self.requestBuffer[..<range.lowerBound])
                let bodyPreread = Data(self.requestBuffer[range.upperBound...])
                self.parseRequest(headersData: headersData, bodyPreread: bodyPreread)
            } else if isComplete {
                self.cancel()
            } else if self.requestBuffer.count < 524_288 {
                self.readRequestHead()
            } else {
                self.cancel()
            }
        }
    }

    // MARK: - Parse request head

    private func parseRequest(headersData: Data, bodyPreread: Data) {
        guard let raw = String(data: headersData, encoding: .utf8) else { cancel(); return }

        let lines  = raw.components(separatedBy: "\r\n")
        let tokens = lines.first.map { $0.split(separator: " ", maxSplits: 2).map(String.init) } ?? []
        guard tokens.count >= 2 else { cancel(); return }

        let method    = tokens[0].uppercased()
        let rawTarget = tokens[1]
        let path  = rawTarget.hasPrefix("http") ? (URL(string: rawTarget)?.path ?? rawTarget) : rawTarget
        let query = URL(string: rawTarget)?.query

        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { break }
            let name  = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers.append((name, value))
        }

        let contentLength = headers
            .first(where: { $0.0.lowercased() == "content-length" })
            .flatMap { Int($0.1) } ?? 0

        let proceed: (Data?) -> Void = { [weak self] body in
            guard let self else { return }
            self.runInterceptionPipeline(method: method, path: path, query: query,
                                        headers: headers, body: body)
        }

        if contentLength > bodyPreread.count {
            readBody(soFar: bodyPreread, remaining: contentLength - bodyPreread.count,
                     completion: proceed)
        } else {
            let body: Data? = contentLength > 0 ? Data(bodyPreread.prefix(contentLength))
                                                : (bodyPreread.isEmpty ? nil : bodyPreread)
            proceed(body)
        }
    }

    private func readBody(soFar: Data, remaining: Int, completion: @escaping (Data?) -> Void) {
        clientConn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, _, error in
            guard let self else { return }
            var acc = soFar
            if let data { acc.append(data) }
            let left = remaining - (data?.count ?? 0)
            if left <= 0 || error != nil { completion(acc.isEmpty ? nil : acc) }
            else { self.readBody(soFar: acc, remaining: left, completion: completion) }
        }
    }

    // MARK: - Interception pipeline (Map Local → Breakpoint → Origin)

    private func runInterceptionPipeline(
        method: String, path: String, query: String?,
        headers: [(String, String)], body: Data?
    ) {
        let queue = networkQueue ?? .global(qos: .userInitiated)

        Task { [weak self] in
            guard let self else { return }

            let normalPath  = path.isEmpty ? "/" : path
            let displayURL  = buildDisplayURL(path: normalPath, query: query)
            let headerFields = headers.map { HTTPHeaderField(name: $0.0, value: $0.1) }

            let tx = ProxyTransaction(
                method: method, scheme: "https",
                host: targetHost, port: targetPort,
                path: normalPath, query: query,
                requestHeaders: headerFields, requestBody: body
            )
            let txID = tx.id

            // ── Step 1: Map Local ───────────────────────────────────────
            let localResp = await MainActor.run {
                MapLocalEngine.shared.localResponse(for: tx)
            }
            if let localResp {
                server.capture(tx)
                server.updateTransaction(
                    id: txID, state: .complete,
                    responseStatusCode: localResp.statusCode,
                    responseStatusMessage: "Map Local",
                    responseHeaders: localResp.headerFields,
                    responseBody: localResp.body
                )
                let raw = buildLocalHTTPResponse(localResp)
                clientConn.send(content: raw,
                                completion: .contentProcessed { [weak self] _ in self?.cancel() })
                return
            }

            server.capture(tx)

            // ── Step 2: Breakpoint ──────────────────────────────────────
            var finalHeaders = headers
            var finalBody    = body

            if let action = await BreakpointEngine.shared.checkIfBreakpointHit(
                url: displayURL, method: method, transaction: tx
            ) {
                switch action {
                case .drop(let code, let msg):
                    server.updateTransaction(id: txID, state: .failed("Dropped by breakpoint"))
                    let r = "HTTP/1.1 \(code) \(msg)\r\nContent-Length: 0\r\n\r\n"
                    clientConn.send(content: r.data(using: .utf8),
                                    completion: .contentProcessed { [weak self] _ in self?.cancel() })
                    return
                case .forward:
                    break
                case .forwardModified(let modHeaders, let modBody):
                    finalHeaders = modHeaders.map { ($0.name, $0.value) }
                    finalBody    = modBody
                }
            }

            // ── Step 3: Forward to origin ───────────────────────────────
            server.updateTransaction(id: txID, state: .active)

            let requestData = buildRawRequest(method: method, path: normalPath, query: query,
                                              headers: finalHeaders, body: finalBody)

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(targetHost),
                port: NWEndpoint.Port(rawValue: UInt16(targetPort)) ?? 443
            )
            // .tls parameters operate below the CFNetwork HTTP-proxy layer and do
            // not inherit system proxy settings — outbound traffic goes direct.
            let origin = NWConnection(to: endpoint, using: .tls)
            originConn = origin

            origin.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    origin.send(content: requestData,
                                completion: .contentProcessed { [weak self] error in
                        guard let self, error == nil else {
                            self?.server.updateTransaction(id: txID, state: .failed("Send failed"))
                            self?.cancel()
                            return
                        }
                        self.relayAndCaptureResponse(from: origin, txID: txID)
                    })
                case .failed(let err):
                    self.server.updateTransaction(id: txID, state: .failed(err.localizedDescription))
                    let r = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n"
                    self.clientConn.send(content: r.data(using: .utf8),
                                         completion: .contentProcessed { _ in self.cancel() })
                case .cancelled:
                    self.clientConn.cancel()
                default: break
                }
            }
            origin.start(queue: queue)
        }
    }

    // MARK: - Relay + capture response from origin

    private func relayAndCaptureResponse(from origin: NWConnection, txID: UUID) {
        var buf = Data()
        var headersFound = false
        var statusCode: Int?
        var statusMsg: String?
        var respHeaders: [HTTPHeaderField] = []

        func recv() {
            origin.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }

                if let data, !data.isEmpty {
                    buf.append(data)
                    clientConn.send(content: data, completion: .contentProcessed { _ in })

                    if !headersFound,
                       let range = buf.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                        headersFound = true
                        let hdrsStr = String(data: Data(buf[..<range.lowerBound]),
                                            encoding: .utf8) ?? ""
                        let lines = hdrsStr.components(separatedBy: "\r\n")
                        if let status = lines.first {
                            let parts = status.split(separator: " ", maxSplits: 2)
                            statusCode = parts.count > 1 ? Int(parts[1]) : nil
                            statusMsg  = parts.count > 2 ? String(parts[2]) : nil
                        }
                        for line in lines.dropFirst() {
                            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { break }
                            let n = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                            let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                            respHeaders.append(HTTPHeaderField(name: n, value: v))
                        }
                    }
                }

                if isComplete || error != nil {
                    let bodySlice = buf.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
                        .map { Data(buf[$0.upperBound...]) }
                    self.server.updateTransaction(
                        id: txID, state: .complete,
                        responseStatusCode: statusCode, responseStatusMessage: statusMsg,
                        responseHeaders: respHeaders, responseBody: bodySlice
                    )
                    self.cancel()
                } else {
                    recv()
                }
            }
        }
        recv()
    }

    // MARK: - Helpers

    private func buildDisplayURL(path: String, query: String?) -> String {
        let q = query.map { "?\($0)" } ?? ""
        let portStr = targetPort == 443 ? "" : ":\(targetPort)"
        return "https://\(targetHost)\(portStr)\(path)\(q)"
    }

    private func buildRawRequest(method: String, path: String, query: String?,
                                 headers: [(String, String)], body: Data?) -> Data {
        let target = query.map { "\(path)?\($0)" } ?? path
        var raw = "\(method) \(target) HTTP/1.1\r\n"
        for (name, value) in headers {
            let lower = name.lowercased()
            if lower == "proxy-connection" || lower == "proxy-authorization" { continue }
            raw += "\(name): \(value)\r\n"
        }
        raw += "\r\n"
        var data = raw.data(using: .utf8)!
        if let body { data.append(body) }
        return data
    }

    private func buildLocalHTTPResponse(_ resp: MapLocalRule.LocalResponse) -> Data {
        let statusText = HTTPURLResponse.localizedString(forStatusCode: resp.statusCode)
        var raw = "HTTP/1.1 \(resp.statusCode) \(statusText)\r\n"
        for h in resp.headerFields { raw += "\(h.name): \(h.value)\r\n" }
        raw += "\r\n"
        var data = raw.data(using: .utf8)!
        data.append(resp.body)
        return data
    }
}
