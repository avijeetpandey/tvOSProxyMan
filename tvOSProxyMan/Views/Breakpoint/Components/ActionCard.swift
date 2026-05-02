import SwiftUI

struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(tint)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(
                focused ? tint.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(focused ? tint : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .focused($focused)
        .padding(.horizontal, 20)
    }
}
