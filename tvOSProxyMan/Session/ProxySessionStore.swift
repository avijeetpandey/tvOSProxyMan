import Foundation

@MainActor
@Observable
final class ProxySessionStore {

    var selectedHost: String? = nil
    var selectedTransactionID: UUID? = nil
    var filterText: String = ""

    // MARK: - Derived sidebar data

    var allHosts: [HostSummary] {
        var map: [String: (count: Int, latest: ProxyTransaction?)] = [:]
        for tx in ProxyServer.shared.transactions {
            var entry = map[tx.host] ?? (count: 0, latest: nil)
            entry.count += 1
            if let prev = entry.latest {
                if tx.timestamp > prev.timestamp { entry.latest = tx }
            } else {
                entry.latest = tx
            }
            map[tx.host] = entry
        }
        return map.map { host, info in
            HostSummary(host: host, requestCount: info.count, latestTransaction: info.latest)
        }.sorted { $0.host < $1.host }
    }

    // MARK: - Transactions for the selected host

    var visibleTransactions: [ProxyTransaction] {
        guard let host = selectedHost else { return [] }
        let all = ProxyServer.shared.transactions
            .filter { $0.host == host }
            .sorted { $0.timestamp > $1.timestamp }
        guard !filterText.isEmpty else { return all }
        let q = filterText.lowercased()
        return all.filter {
            $0.path.lowercased().contains(q) ||
            $0.method.lowercased().contains(q) ||
            ($0.responseStatusCode.map { "\($0)" } ?? "").contains(q)
        }
    }

    // MARK: - Selected transaction

    var selectedTransaction: ProxyTransaction? {
        guard let id = selectedTransactionID else { return nil }
        return ProxyServer.shared.transactions.first { $0.id == id }
    }

    // MARK: - Server passthrough

    var isRunning: Bool            { ProxyServer.shared.isRunning }
    var listeningPort: UInt16      { ProxyServer.shared.listeningPort }
    var lastError: String?         { ProxyServer.shared.lastError }
    var activeConnections: Int     { ProxyServer.shared.activeConnectionCount }
    var totalRequestCount: Int     { ProxyServer.shared.transactions.count }

    func startProxy()  { ProxyServer.shared.start() }
    func stopProxy()   { ProxyServer.shared.stop()  }

    func clearAll() {
        ProxyServer.shared.clearTransactions()
        selectedHost = nil
        selectedTransactionID = nil
        filterText = ""
    }
}
