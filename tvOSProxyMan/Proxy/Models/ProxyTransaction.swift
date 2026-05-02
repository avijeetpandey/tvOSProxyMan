import Foundation

struct ProxyTransaction: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date

    var method: String
    var scheme: String
    var host: String
    var port: Int
    var path: String
    var query: String?

    var requestHeaders: [HTTPHeaderField]
    var requestBody: Data?

    var responseStatusCode: Int?
    var responseStatusMessage: String?
    var responseHeaders: [HTTPHeaderField]
    var responseBody: Data?

    var state: TransactionState
    var startTime: Date
    var endTime: Date?

    // True when the request originated from this device (127.0.0.1 / ::1 client,
    // or intercepted via ProxyURLProtocol rather than the NWListener).
    let isLocalTraffic: Bool

    var duration: TimeInterval? {
        endTime.map { $0.timeIntervalSince(startTime) }
    }

    var displayURL: String {
        let pathWithQuery = query.map { "\(path)?\($0)" } ?? (path.isEmpty ? "/" : path)
        let showPort = (scheme == "http" && port != 80) || (scheme == "https" && port != 443)
        let portStr = showPort ? ":\(port)" : ""
        return "\(scheme)://\(host)\(portStr)\(pathWithQuery)"
    }

    var statusBadgeColor: String {
        guard let code = responseStatusCode else { return "gray" }
        switch code {
        case 200..<300: return "green"
        case 300..<400: return "yellow"
        case 400..<500: return "orange"
        default:        return "red"
        }
    }

    init(
        method: String,
        scheme: String,
        host: String,
        port: Int,
        path: String,
        query: String? = nil,
        requestHeaders: [HTTPHeaderField],
        requestBody: Data? = nil,
        isLocalTraffic: Bool = false
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.startTime = Date()
        self.method = method
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.query = query
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseHeaders = []
        self.state = .pending
        self.isLocalTraffic = isLocalTraffic
    }
}
