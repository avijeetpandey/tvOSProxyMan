import Foundation
import Network
import Security
import os.log

final class ProxyConnection {
    let id = UUID()

    private let clientConnection: NWConnection
    private var serverConnection: NWConnection?
    private var mitmListener: NWListener?
    private var requestBuffer = Data()

    private unowned let server: ProxyServer
    private let logger = Logger(subsystem: "com.tvOSProxyMan", category: "ProxyConnection")
    private var networkQueue: DispatchQueue?

    init(nwConnection: NWConnection, server: ProxyServer) {
        self.clientConnection = nwConnection
        self.server = server
    }

    func start(on queue: DispatchQueue) {
        networkQueue = queue
        clientConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:    self.readRequestHead()
            case .failed, .cancelled: self.cleanup()
            default: break
            }
        }
        clientConnection.start(queue: queue)
    }

    func cancel() {
        mitmListener?.cancel()
        clientConnection.cancel()
        serverConnection?.cancel()
    }

    private func cleanup() {
        mitmListener?.cancel()
        serverConnection?.cancel()
        server.connectionDidClose(id)
    }

    // MARK: - Read initial request head

    private func readRequestHead() {
        clientConnection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil && data == nil { self.cancel(); return }
            if let data { self.requestBuffer.append(data) }

            let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
            if let range = self.requestBuffer.range(of: terminator) {
                let headersData = Data(self.requestBuffer[..<range.lowerBound])
                let bodyPreread = Data(self.requestBuffer[range.upperBound...])
                self.parseAndDispatch(headersData: headersData, bodyPreread: bodyPreread)
            } else if isComplete {
                self.cancel()
            } else if self.requestBuffer.count < 524_288 {
                self.readRequestHead()
            } else {
                self.respond(status: "413 Request Header Fields Too Large")
            }
        }
    }

    // MARK: - Parse request line + headers

    private func parseAndDispatch(headersData: Data, bodyPreread: Data) {
        guard let raw = String(data: headersData, encoding: .utf8) else {
            respond(status: "400 Bad Request"); return
        }
        let lines  = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            respond(status: "400 Bad Request"); return
        }
        let tokens = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard tokens.count >= 2 else { respond(status: "400 Bad Request"); return }

        let method = tokens[0].uppercased()
        let target = tokens[1]

        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { break }
            let name  = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers.append((name: name, value: value))
        }

        if method == "CONNECT" {
            handleCONNECT(target: target, headers: headers)
        } else {
            handleHTTP(method: method, target: target, headers: headers, bodyPreread: bodyPreread)
        }
    }

    // MARK: - CONNECT — MITM TLS interception with transparent-tunnel fallback

    private func handleCONNECT(target: String, headers: [(name: String, value: String)]) {
        let (host, port) = splitHostPort(target, default: 443)
        logger.debug("CONNECT \(host):\(port)")

        let tx = ProxyTransaction(
            method: "CONNECT", scheme: "https",
            host: host, port: port, path: "",
            requestHeaders: headers.map { HTTPHeaderField(name: $0.name, value: $0.value) }
        )
        let txID = tx.id
        server.capture(tx)

        let ok = "HTTP/1.1 200 Connection Established\r\nProxy-Agent: tvOSProxyMan/1.0\r\n\r\n"
        clientConnection.send(content: ok.data(using: .utf8),
                              completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { self?.cancel(); return }
            do {
                try self.startMITM(host: host, port: port, txID: txID)
            } catch {
                self.logger.warning("MITM failed, using transparent tunnel: \(error)")
                self.server.updateTransaction(id: txID, state: .tunneled)
                self.startTransparentTunnel(host: host, port: port, txID: txID)
            }
        })
    }

    // MARK: - MITM TLS setup

    private func startMITM(host: String, port: Int, txID: UUID) throws {
        let identity = try CertificateManager.shared.leafIdentity(for: host)

        guard let secID = sec_identity_create(identity) else {
            throw CertificateError.identityNotFound
        }

        let tlsOpts = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tlsOpts.securityProtocolOptions, secID)
        sec_protocol_options_set_peer_authentication_required(
            tlsOpts.securityProtocolOptions, false
        )

        let params = NWParameters(tls: tlsOpts)
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params)
        mitmListener = listener

        listener.newConnectionHandler = { [weak self] decryptedConn in
            guard let self else { return }
            let mitm = MITMConnection(
                decryptedConn: decryptedConn,
                targetHost: host, targetPort: port,
                server: self.server
            )
            mitm.start(on: self.networkQueue ?? .global(qos: .userInitiated))
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let listenerPort = listener.port?.rawValue else { return }
                self.createBridge(toLocalPort: listenerPort)
            case .failed(let err):
                self.logger.error("MITM listener failed: \(err)")
                self.server.updateTransaction(id: txID,
                    state: .failed("MITM listener: \(err.localizedDescription)"))
                self.cancel()
            default: break
            }
        }

        let queue = networkQueue ?? .global(qos: .userInitiated)
        listener.start(queue: queue)
    }

    private func createBridge(toLocalPort port: UInt16) {
        let bridge = NWConnection(
            to: .hostPort(host: "127.0.0.1",
                          port: NWEndpoint.Port(rawValue: port)!),
            using: .tcp
        )
        serverConnection = bridge

        bridge.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.pipe(self.clientConnection, to: bridge)
                self.pipe(bridge, to: self.clientConnection)
            case .failed(let err):
                self.logger.debug("Bridge failed: \(err)")
                self.cancel()
            case .cancelled:
                self.clientConnection.cancel()
            default: break
            }
        }
        bridge.start(queue: networkQueue ?? .global(qos: .userInitiated))
    }

    // MARK: - Transparent TCP tunnel (MITM fallback)

    private func startTransparentTunnel(host: String, port: Int, txID: UUID) {
        let remote = makeConnection(host: host, port: port, tls: false)
        serverConnection = remote

        remote.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.pipe(self.clientConnection, to: remote)
                self.pipe(remote, to: self.clientConnection)
            case .failed(let err):
                self.server.updateTransaction(id: txID, state: .failed(err.localizedDescription))
                self.cancel()
            case .cancelled:
                self.clientConnection.cancel()
            default: break
            }
        }
        remote.start(queue: networkQueue ?? .global(qos: .userInitiated))
    }

    // MARK: - Plain HTTP

    private func handleHTTP(method: String, target: String,
                            headers: [(name: String, value: String)], bodyPreread: Data) {
        guard let url = URL(string: target), let host = url.host, !host.isEmpty else {
            respond(status: "400 Bad Request"); return
        }
        let port  = url.port ?? 80
        let path  = url.path.isEmpty ? "/" : url.path
        let query = url.query

        let contentLength = headers
            .first(where: { $0.name.lowercased() == "content-length" })
            .flatMap { Int($0.value) } ?? 0

        let dispatch: (Data?) -> Void = { [weak self] body in
            guard let self else { return }
            self.forwardHTTP(method: method, host: host, port: port,
                             path: path, query: query, headers: headers, body: body)
        }

        if contentLength > bodyPreread.count {
            readBody(soFar: bodyPreread, remaining: contentLength - bodyPreread.count,
                     completion: dispatch)
        } else {
            let body: Data? = contentLength > 0 ? Data(bodyPreread.prefix(contentLength))
                                                : (bodyPreread.isEmpty ? nil : bodyPreread)
            dispatch(body)
        }
    }

    private func readBody(soFar: Data, remaining: Int, completion: @escaping (Data?) -> Void) {
        clientConnection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, _, error in
            guard let self else { return }
            var acc = soFar
            if let data { acc.append(data) }
            let left = remaining - (data?.count ?? 0)
            if left <= 0 || error != nil { completion(acc.isEmpty ? nil : acc) }
            else { self.readBody(soFar: acc, remaining: left, completion: completion) }
        }
    }

    private func forwardHTTP(method: String, host: String, port: Int,
                             path: String, query: String?,
                             headers: [(name: String, value: String)], body: Data?) {
        logger.debug("HTTP \(method) \(host):\(port)\(path)")

        let queue = networkQueue ?? .global(qos: .userInitiated)
        let displayURL = "http://\(host)\(port == 80 ? "" : ":\(port)")\(path)\(query.map { "?\($0)" } ?? "")"

        Task { [weak self] in
            guard let self else { return }

            let tx = ProxyTransaction(
                method: method, scheme: "http", host: host, port: port,
                path: path, query: query,
                requestHeaders: headers.map { HTTPHeaderField(name: $0.name, value: $0.value) },
                requestBody: body
            )
            let txID = tx.id

            let localResp = await MainActor.run { MapLocalEngine.shared.localResponse(for: tx) }
            if let localResp {
                self.server.capture(tx)
                self.server.updateTransaction(
                    id: txID, state: .complete,
                    responseStatusCode: localResp.statusCode,
                    responseStatusMessage: "Map Local",
                    responseHeaders: localResp.headerFields,
                    responseBody: localResp.body
                )
                let raw = self.buildLocalHTTPResponse(localResp)
                self.clientConnection.send(content: raw,
                    completion: .contentProcessed { [weak self] _ in self?.cancel() })
                return
            }

            self.server.capture(tx)

            var finalHeaders = headers
            var finalBody    = body

            if let action = await BreakpointEngine.shared.checkIfBreakpointHit(
                url: displayURL, method: method, transaction: tx
            ) {
                switch action {
                case .drop(let code, let msg):
                    self.server.updateTransaction(id: txID, state: .failed("Dropped by breakpoint"))
                    let r = "HTTP/1.1 \(code) \(msg)\r\nContent-Length: 0\r\n\r\n"
                    self.clientConnection.send(content: r.data(using: .utf8),
                        completion: .contentProcessed { [weak self] _ in self?.cancel() })
                    return
                case .forward: break
                case .forwardModified(let modH, let modB):
                    finalHeaders = modH.map { ($0.name, $0.value) }
                    finalBody    = modB
                }
            }

            self.server.updateTransaction(id: txID, state: .active)

            let requestData = self.buildRawRequest(
                method: method, path: path, query: query,
                headers: finalHeaders, body: finalBody
            )
            let remote = self.makeConnection(host: host, port: port, tls: false)
            self.serverConnection = remote

            remote.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    remote.send(content: requestData,
                                completion: .contentProcessed { [weak self] error in
                        guard let self, error == nil else {
                            self?.server.updateTransaction(id: txID, state: .failed("Send failed"))
                            self?.cancel(); return
                        }
                        self.relayHTTPResponse(from: remote, txID: txID)
                    })
                case .failed(let err):
                    self.server.updateTransaction(id: txID, state: .failed(err.localizedDescription))
                    self.respond(status: "502 Bad Gateway")
                case .cancelled:
                    self.clientConnection.cancel()
                default: break
                }
            }
            remote.start(queue: queue)
        }
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

    // MARK: - HTTP response relay

    private func relayHTTPResponse(from remote: NWConnection, txID: UUID) {
        var buf = Data()
        var headersFound = false
        var statusCode: Int?
        var statusMsg: String?
        var respHeaders: [HTTPHeaderField] = []

        func recv() {
            remote.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    buf.append(data)
                    self.clientConnection.send(content: data, completion: .contentProcessed { _ in })

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
                        responseStatusCode: statusCode,
                        responseStatusMessage: statusMsg,
                        responseHeaders: respHeaders,
                        responseBody: bodySlice
                    )
                    self.cancel()
                } else { recv() }
            }
        }
        recv()
    }

    // MARK: - Bidirectional TCP pipe

    private func pipe(_ source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil { destination.cancel() }
            else { self.pipe(source, to: destination) }
        }
    }

    // MARK: - Helpers

    private func makeConnection(host: String, port: Int, tls: Bool) -> NWConnection {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 80
        )
        return NWConnection(to: endpoint, using: tls ? .tls : .tcp)
    }

    private func buildRawRequest(method: String, path: String, query: String?,
                                 headers: [(name: String, value: String)], body: Data?) -> Data {
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

    private func splitHostPort(_ s: String, default defaultPort: Int) -> (String, Int) {
        if let colon = s.lastIndex(of: ":") {
            let portStr = String(s[s.index(after: colon)...])
            if let port = Int(portStr) { return (String(s[..<colon]), port) }
        }
        return (s, defaultPort)
    }

    private func respond(status: String) {
        let r = "HTTP/1.1 \(status)\r\nProxy-Agent: tvOSProxyMan/1.0\r\nContent-Length: 0\r\n\r\n"
        clientConnection.send(
            content: r.data(using: .utf8),
            completion: .contentProcessed { [weak self] _ in self?.cancel() }
        )
    }
}
