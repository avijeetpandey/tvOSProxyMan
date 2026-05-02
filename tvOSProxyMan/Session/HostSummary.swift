import SwiftUI

struct HostSummary: Identifiable {
    var id: String { host }
    let host: String
    let requestCount: Int
    let latestTransaction: ProxyTransaction?

    var latestStatusColor: Color {
        guard let code = latestTransaction?.responseStatusCode else { return .secondary }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .yellow
        case 400..<500: return .orange
        default:        return .red
        }
    }
}
