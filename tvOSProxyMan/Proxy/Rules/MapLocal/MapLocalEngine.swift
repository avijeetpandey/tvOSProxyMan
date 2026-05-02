import Foundation

@MainActor
@Observable
final class MapLocalEngine {
    static let shared = MapLocalEngine()

    var rules: [MapLocalRule] = []

    private init() {}

    func localResponse(for transaction: ProxyTransaction) -> MapLocalRule.LocalResponse? {
        rules
            .first { $0.matches(url: transaction.displayURL, method: transaction.method) }
            .map   { $0.buildLocalResponse() }
    }

    // MARK: - Rule management

    func addRule(urlPattern: String,
                 responseBody: String = "{}",
                 statusCode: Int = 200,
                 contentType: String = "application/json") {
        rules.append(MapLocalRule(urlPattern: urlPattern,
                                  statusCode: statusCode,
                                  responseBody: responseBody,
                                  contentType: contentType))
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func toggleRule(id: UUID) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].isEnabled.toggle()
    }
}
