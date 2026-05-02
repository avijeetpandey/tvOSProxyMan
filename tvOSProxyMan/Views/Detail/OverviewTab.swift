import SwiftUI

struct OverviewTab: View {
    let tx: ProxyTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            InfoCard(title: "URL") {
                Text(tx.displayURL)
                    .font(.system(.body, design: .monospaced))
                    // textSelection not available on tvOS
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 24) {
                MetricTile(label: "Method",   value: tx.method)
                MetricTile(label: "Status",   value: tx.responseStatusCode.map { "\($0)" } ?? "—",
                           color: statusColor(tx.responseStatusCode))
                MetricTile(label: "Duration", value: tx.duration.map { durationStr($0) } ?? "—")
                MetricTile(label: "Scheme",   value: tx.scheme.uppercased())
            }

            if let msg = tx.responseStatusMessage {
                InfoCard(title: "Status Message") {
                    Text(msg).font(.body)
                }
            }

            InfoCard(title: "Timing") {
                LabeledContent("Started", value: tx.startTime.formatted(date: .omitted,
                                                                         time: .standard))
                if let end = tx.endTime {
                    LabeledContent("Completed", value: end.formatted(date: .omitted,
                                                                      time: .standard))
                }
                if let dur = tx.duration {
                    LabeledContent("Elapsed", value: durationStr(dur))
                }
            }
        }
        .padding(40)
    }

    private func durationStr(_ d: TimeInterval) -> String {
        d < 1 ? String(format: "%.0f ms", d * 1000) : String(format: "%.2f s", d)
    }

    private func statusColor(_ code: Int?) -> Color {
        guard let c = code else { return .secondary }
        switch c {
        case 200..<300: return .green
        case 300..<400: return .yellow
        case 400..<500: return .orange
        default:        return .red
        }
    }
}
