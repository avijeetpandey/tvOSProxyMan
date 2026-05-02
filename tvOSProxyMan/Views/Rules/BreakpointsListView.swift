import SwiftUI

struct BreakpointsListView: View {
    @Binding var showAdd: Bool

    var body: some View {
        let engine = BreakpointEngine.shared
        if engine.breakpoints.isEmpty {
            ContentUnavailableView(
                "No Breakpoints",
                systemImage: "pause.circle",
                description: Text("Tap + to add a URL pattern.\nMatching requests will pause for inspection.")
            )
        } else {
            List {
                ForEach(engine.breakpoints) { bp in
                    BreakpointRowView(breakpoint: bp)
                }
                .onDelete { offsets in
                    offsets.forEach { engine.removeBreakpoint(id: engine.breakpoints[$0].id) }
                }
            }
            .listStyle(.grouped)
        }
    }
}
