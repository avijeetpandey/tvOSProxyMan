import SwiftUI

struct TabBarButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                .foregroundStyle(selected ? .primary : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
