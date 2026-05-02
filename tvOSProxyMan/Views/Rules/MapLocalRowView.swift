import SwiftUI

struct MapLocalRowView: View {
    let rule: MapLocalRule

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .foregroundStyle(rule.isEnabled ? .blue : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name).font(.headline)
                Text(rule.urlPattern)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(rule.statusCode)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    Text(rule.contentType)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in MapLocalEngine.shared.toggleRule(id: rule.id) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
