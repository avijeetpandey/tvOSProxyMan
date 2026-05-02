import SwiftUI

struct RequestRowView: View {
    let transaction: ProxyTransaction
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            MethodBadge(method: transaction.method)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.path.isEmpty ? "/" : transaction.path)
                    .font(.headline)
                    .lineLimit(1)
                if let q = transaction.query {
                    Text("?\(q)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(code: transaction.responseStatusCode,
                            state: transaction.state)
                if let dur = transaction.duration {
                    Text(durationString(dur))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .focused($focused)
    }

    private func durationString(_ d: TimeInterval) -> String {
        d < 1 ? String(format: "%.0f ms", d * 1000)
              : String(format: "%.2f s", d)
    }
}
