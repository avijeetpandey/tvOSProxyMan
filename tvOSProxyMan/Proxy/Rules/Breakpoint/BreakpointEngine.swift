import Foundation
import os.log

@MainActor
@Observable
final class BreakpointEngine {
    static let shared = BreakpointEngine()

    var breakpoints: [Breakpoint] = []
    var pausedRequests: [PausedRequest] = []

    private let logger = Logger(subsystem: "com.tvOSProxyMan", category: "BreakpointEngine")

    private init() {}

    // MARK: - Network-side entry point

    nonisolated func checkIfBreakpointHit(
        url: String,
        method: String,
        transaction: ProxyTransaction
    ) async -> BreakpointAction? {
        let matches = await MainActor.run {
            self.breakpoints.contains { $0.matches(url: url, method: method) }
        }
        guard matches else { return nil }

        logger.debug("Breakpoint hit: \(method) \(url)")

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pausedRequests.append(
                    PausedRequest(id: transaction.id, transaction: transaction,
                                  displayURL: url, continuation: continuation)
                )
            }
        }
    }

    // MARK: - UI-side resolution

    func forward(id: UUID) {
        resolve(.forward, id: id)
    }

    func drop(id: UUID, statusCode: Int = 503, message: String = "Dropped by Breakpoint") {
        resolve(.drop(statusCode: statusCode, message: message), id: id)
    }

    func forwardModified(id: UUID) {
        guard let idx = pausedRequests.firstIndex(where: { $0.id == id }) else { return }
        let req = pausedRequests[idx]
        let body = req.editedBody.isEmpty ? nil : req.editedBody.data(using: .utf8)
        resolve(.forwardModified(headers: req.editedHeaders, body: body), id: id)
    }

    private func resolve(_ action: BreakpointAction, id: UUID) {
        guard let idx = pausedRequests.firstIndex(where: { $0.id == id }) else { return }
        let req = pausedRequests.remove(at: idx)
        req.continuation.resume(returning: action)
    }

    func dropAll() {
        while let req = pausedRequests.first {
            resolve(.drop(statusCode: 503, message: "Proxy stopped"), id: req.id)
        }
    }

    // MARK: - Rule management

    func addBreakpoint(urlPattern: String, methods: Set<String> = []) {
        breakpoints.append(Breakpoint(urlPattern: urlPattern, methods: methods))
    }

    func removeBreakpoint(id: UUID) {
        breakpoints.removeAll { $0.id == id }
    }

    func toggleBreakpoint(id: UUID) {
        guard let idx = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[idx].isEnabled.toggle()
    }
}
