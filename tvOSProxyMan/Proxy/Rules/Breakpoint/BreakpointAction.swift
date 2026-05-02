import Foundation

enum BreakpointAction: Sendable {
    case forward
    case drop(statusCode: Int, message: String)
    case forwardModified(headers: [HTTPHeaderField], body: Data?)
}
