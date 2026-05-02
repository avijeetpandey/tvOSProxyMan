import Foundation

struct HTTPHeaderField: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let value: String

    init(name: String, value: String) {
        self.id = UUID()
        self.name = name
        self.value = value
    }
}
