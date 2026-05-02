import SwiftUI

struct MethodBadge: View {
    let method: String

    private var color: Color {
        switch method {
        case "GET":             return .blue
        case "POST":            return .green
        case "PUT", "PATCH":    return .orange
        case "DELETE":          return .red
        case "CONNECT":         return .purple
        case "HEAD":            return .teal
        default:                return .gray
        }
    }

    var body: some View {
        Text(method)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(color)
    }
}
