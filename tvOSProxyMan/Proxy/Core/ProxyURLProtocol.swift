import Foundation

final class ProxyURLProtocol: URLProtocol {

    private static let handledKey = "com.tvOSProxyMan.handled"

    // Session that bypasses both this protocol and the system proxy so forwarded
    // requests don't re-enter the interception pipeline or loop through 127.0.0.1:9090.
    private static let bypassSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = []            // prevents re-entry via URLProtocol
        cfg.connectionProxyDictionary = [:] // bypasses system HTTP proxy settings
        return URLSession(configuration: cfg)
    }()

    private var loadingTask: Task<Void, Never>?

    // MARK: - URLProtocol hooks

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        let scheme = request.url?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        loadingTask = Task { await handleRequest() }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }

    // MARK: - Interception pipeline (Map Local → Breakpoint → Forward)

    private func handleRequest() async {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        let scheme = url.scheme ?? "https"
        let port   = url.port ?? (scheme == "https" ? 443 : 80)
        let path   = url.path.isEmpty ? "/" : url.path

        let reqHeaders = (request.allHTTPHeaderFields ?? [:])
            .map { HTTPHeaderField(name: $0.key, value: $0.value) }

        let tx = ProxyTransaction(
            method: method, scheme: scheme,
            host: host, port: port,
            path: path, query: url.query,
            requestHeaders: reqHeaders,
            requestBody: request.httpBody
        )
        let txID = tx.id

        // ── Step 1: Map Local ──────────────────────────────────────────────
        let localResp = await MainActor.run {
            MapLocalEngine.shared.localResponse(for: tx)
        }
        if let localResp {
            ProxyServer.shared.capture(tx)
            ProxyServer.shared.updateTransaction(
                id: txID, state: .complete,
                responseStatusCode: localResp.statusCode,
                responseStatusMessage: "Map Local",
                responseHeaders: localResp.headerFields,
                responseBody: localResp.body
            )
            serveLocalResponse(localResp, url: url)
            return
        }

        ProxyServer.shared.capture(tx)

        // Tag the request so canInit rejects it if it re-enters this protocol.
        let mutableReq = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableReq)
        var forwardRequest = mutableReq as URLRequest

        // ── Step 2: Breakpoint ─────────────────────────────────────────────
        if let action = await BreakpointEngine.shared.checkIfBreakpointHit(
            url: url.absoluteString, method: method, transaction: tx
        ) {
            switch action {
            case .drop(let code, let msg):
                ProxyServer.shared.updateTransaction(id: txID, state: .failed("Dropped by breakpoint"))
                let err = URLError(.cancelled, userInfo: [
                    NSLocalizedDescriptionKey: "Dropped by breakpoint: \(code) \(msg)"
                ])
                client?.urlProtocol(self, didFailWithError: err)
                return
            case .forward:
                break
            case .forwardModified(let modHeaders, let modBody):
                let mutable2 = (forwardRequest as NSURLRequest).mutableCopy() as! NSMutableURLRequest
                for h in modHeaders { mutable2.setValue(h.value, forHTTPHeaderField: h.name) }
                mutable2.httpBody = modBody
                forwardRequest = mutable2 as URLRequest
            }
        }

        ProxyServer.shared.updateTransaction(id: txID, state: .active)

        // ── Step 3: Forward via bypass session ─────────────────────────────
        do {
            let (data, response) = try await Self.bypassSession.data(for: forwardRequest)
            guard !Task.isCancelled else { return }

            if let httpResp = response as? HTTPURLResponse {
                let respHeaders = httpResp.allHeaderFields.compactMap { k, v -> HTTPHeaderField? in
                    guard let name = k as? String else { return nil }
                    return HTTPHeaderField(name: name, value: "\(v)")
                }
                ProxyServer.shared.updateTransaction(
                    id: txID, state: .complete,
                    responseStatusCode: httpResp.statusCode,
                    responseStatusMessage: HTTPURLResponse.localizedString(
                        forStatusCode: httpResp.statusCode),
                    responseHeaders: respHeaders,
                    responseBody: data
                )
                client?.urlProtocol(self, didReceive: httpResp, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)

        } catch {
            guard !Task.isCancelled else { return }
            ProxyServer.shared.updateTransaction(id: txID, state: .failed(error.localizedDescription))
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func serveLocalResponse(_ resp: MapLocalRule.LocalResponse, url: URL) {
        let headerDict = Dictionary(
            resp.headerFields.map { ($0.name, $0.value) },
            uniquingKeysWith: { $1 }
        )
        guard let httpResp = HTTPURLResponse(
            url: url, statusCode: resp.statusCode,
            httpVersion: "HTTP/1.1", headerFields: headerDict
        ) else { return }
        client?.urlProtocol(self, didReceive: httpResp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: resp.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
