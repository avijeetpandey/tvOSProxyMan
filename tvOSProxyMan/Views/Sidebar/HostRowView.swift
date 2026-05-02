import SwiftUI

struct HostRowView: View {
    let summary: HostSummary
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(summary.latestStatusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.host)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(summary.requestCount) request\(summary.requestCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let latest = summary.latestTransaction {
                StatusBadge(code: latest.responseStatusCode)
            }
        }
        .padding(.vertical, 4)
        .focused($focused)
    }
}
