import Foundation

// Represents a network request that has been suspended pending a user decision.
// The continuation is marked internal so BreakpointEngine can resume it.
struct PausedRequest: Identifiable, @unchecked Sendable {
    let id: UUID
    let transaction: ProxyTransaction
    let displayURL: String
    var editedHeaders: [HTTPHeaderField]
    var editedBody: String
    let continuation: CheckedContinuation<BreakpointAction, Never>

    init(id: UUID, transaction: ProxyTransaction, displayURL: String,
         continuation: CheckedContinuation<BreakpointAction, Never>) {
        self.id            = id
        self.transaction   = transaction
        self.displayURL    = displayURL
        self.editedHeaders = transaction.requestHeaders
        self.editedBody    = transaction.requestBody
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        self.continuation  = continuation
    }
}
