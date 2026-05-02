import Foundation

struct Breakpoint: Identifiable, Sendable {
    let id: UUID
    var name: String
    var urlPattern: String
    var methods: Set<String>
    var isEnabled: Bool

    init(name: String = "", urlPattern: String,
         methods: Set<String> = [], isEnabled: Bool = true) {
        self.id         = UUID()
        self.name       = name.isEmpty ? urlPattern : name
        self.urlPattern = urlPattern
        self.methods    = methods
        self.isEnabled  = isEnabled
    }

    func matches(url: String, method: String) -> Bool {
        guard isEnabled else { return false }
        if !methods.isEmpty && !methods.contains(method.uppercased()) { return false }
        return patternMatches(urlPattern, url: url)
    }
}
