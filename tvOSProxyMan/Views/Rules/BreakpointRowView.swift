import SwiftUI

struct BreakpointRowView: View {
    let breakpoint: Breakpoint

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(breakpoint.isEnabled ? .orange : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(breakpoint.name).font(.headline)
                Text(breakpoint.urlPattern)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !breakpoint.methods.isEmpty {
                    Text(breakpoint.methods.sorted().joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { breakpoint.isEnabled },
                set: { _ in BreakpointEngine.shared.toggleBreakpoint(id: breakpoint.id) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
