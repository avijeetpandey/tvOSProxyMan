import SwiftUI

struct BreakpointModalView: View {
    let requestID: UUID
    @State private var mode: Mode = .deciding
    @FocusState private var focusedAction: ActionButton?

    private enum Mode { case deciding, editing }
    private enum ActionButton: Hashable { case forward, drop, edit }

    var body: some View {
        let engine = BreakpointEngine.shared
        guard let idx = engine.pausedRequests.firstIndex(where: { $0.id == requestID }) else {
            return AnyView(ProgressView("Resolving…"))
        }
        let req = engine.pausedRequests[idx]

        return AnyView(
            HStack(spacing: 0) {
                // ── Left panel: request details ──────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        BreakpointHeaderSection(req: req)

                        if mode == .editing {
                            BreakpointEditSection(requestID: requestID)
                        } else {
                            BreakpointReadOnlySection(req: req)
                        }
                    }
                    .padding(40)
                }
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)

                Divider()

                // ── Right panel: actions ─────────────────────────────────
                VStack(spacing: 24) {
                    Text("Action")
                        .font(.title2.bold())
                        .padding(.top, 40)

                    Spacer()

                    ActionCard(
                        title:    "Forward",
                        subtitle: "Continue with the original request",
                        icon:     "arrow.forward.circle.fill",
                        tint:     .green
                    ) {
                        engine.forward(id: requestID)
                    }
                    .focused($focusedAction, equals: .forward)

                    ActionCard(
                        title:    "Drop",
                        subtitle: "Return 503 to the client",
                        icon:     "xmark.circle.fill",
                        tint:     .red
                    ) {
                        engine.drop(id: requestID)
                    }
                    .focused($focusedAction, equals: .drop)

                    ActionCard(
                        title:    mode == .editing ? "Send Modified" : "Edit & Forward",
                        subtitle: mode == .editing ? "Forward with your changes"
                                                   : "Modify headers / body first",
                        icon:     mode == .editing ? "paperplane.circle.fill"
                                                   : "pencil.circle.fill",
                        tint:     .orange
                    ) {
                        if mode == .editing {
                            engine.forwardModified(id: requestID)
                        } else {
                            withAnimation { mode = .editing }
                        }
                    }
                    .focused($focusedAction, equals: .edit)

                    Spacer()

                    Text("Breakpoint Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 32)
                }
                .frame(width: 420)
                .background(.thinMaterial)
            }
            .ignoresSafeArea()
            .onAppear { focusedAction = .forward }
        )
    }
}
