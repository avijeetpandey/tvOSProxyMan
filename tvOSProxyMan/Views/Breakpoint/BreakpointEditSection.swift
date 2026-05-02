import SwiftUI

struct BreakpointEditSection: View {
    let requestID: UUID

    var body: some View {
        let engine = BreakpointEngine.shared
        guard let idx = engine.pausedRequests.firstIndex(where: { $0.id == requestID }) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle("Edit Request Body")

                TextField("Request body", text: Binding(
                    get: { engine.pausedRequests[idx].editedBody },
                    set: { engine.pausedRequests[idx].editedBody = $0 }
                ), axis: .vertical)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(8...)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
        )
    }
}
