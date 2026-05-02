import SwiftUI

struct BreakpointHeaderSection: View {
    let req: PausedRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Breakpoint Hit", systemImage: "pause.circle.fill")
                .font(.title.bold())
                .foregroundStyle(.orange)

            Text(req.displayURL)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                // textSelection not available on tvOS

            HStack {
                MethodBadge(method: req.transaction.method)
                Text(req.transaction.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
