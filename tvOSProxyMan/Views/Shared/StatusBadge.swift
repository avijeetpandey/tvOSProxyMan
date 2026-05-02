import SwiftUI

struct StatusBadge: View {
    let code: Int?
    var state: TransactionState = .complete

    private var effectiveCode: Int? {
        if case .tunneled = state { return nil }
        return code
    }

    private var color: Color {
        guard let c = effectiveCode else { return .secondary }
        switch c {
        case 200..<300: return .green
        case 300..<400: return .yellow
        case 400..<500: return .orange
        default:        return .red
        }
    }

    var body: some View {
        Group {
            switch state {
            case .pending, .active:
                ProgressView().scaleEffect(0.55)
            case .tunneled:
                Text("TLS").font(.caption.bold()).foregroundStyle(.purple)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            case .complete:
                if let c = effectiveCode {
                    Text("\(c)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(color)
                }
            }
        }
    }
}
