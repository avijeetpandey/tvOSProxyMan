import Foundation

struct MapLocalRule: Identifiable, Sendable {
    let id: UUID
    var name: String
    var urlPattern: String
    var methods: Set<String>
    var statusCode: Int
    var responseBody: String
    var contentType: String
    var isEnabled: Bool

    struct LocalResponse: Sendable {
        let statusCode: Int
        let headerFields: [HTTPHeaderField]
        let body: Data
    }

    init(name: String = "", urlPattern: String,
         methods: Set<String> = [],
         statusCode: Int = 200,
         responseBody: String = "{}",
         contentType: String = "application/json",
         isEnabled: Bool = true) {
        self.id           = UUID()
        self.name         = name.isEmpty ? urlPattern : name
        self.urlPattern   = urlPattern
        self.methods      = methods
        self.statusCode   = statusCode
        self.responseBody = responseBody
        self.contentType  = contentType
        self.isEnabled    = isEnabled
    }

    func matches(url: String, method: String) -> Bool {
        guard isEnabled else { return false }
        if !methods.isEmpty && !methods.contains(method.uppercased()) { return false }
        return patternMatches(urlPattern, url: url)
    }

    func buildLocalResponse() -> LocalResponse {
        let bodyData = responseBody.data(using: .utf8) ?? Data()
        return LocalResponse(
            statusCode: statusCode,
            headerFields: [
                HTTPHeaderField(name: "Content-Type",   value: contentType),
                HTTPHeaderField(name: "Content-Length", value: "\(bodyData.count)"),
                HTTPHeaderField(name: "X-Served-By",    value: "tvOSProxyMan/MapLocal")
            ],
            body: bodyData
        )
    }
}
