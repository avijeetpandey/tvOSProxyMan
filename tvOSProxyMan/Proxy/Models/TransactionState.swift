import Foundation

enum TransactionState: Sendable, Equatable {
    case pending
    case active
    case complete
    case failed(String)
    case tunneled

    static func == (lhs: TransactionState, rhs: TransactionState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.active, .active), (.complete, .complete), (.tunneled, .tunneled):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
