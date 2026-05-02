import SwiftUI

struct HostSidebarView: View {
    @Environment(ProxySessionStore.self) private var store
    @Binding var showRules: Bool

    var body: some View {
        @Bindable var store = store

        List(store.allHosts, selection: $store.selectedHost) { summary in
            HostRowView(summary: summary)
                .tag(summary.host)
        }
        .listStyle(.plain)
        .navigationTitle("tvOSProxyMan")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                let ruleCount = BreakpointEngine.shared.breakpoints.filter(\.isEnabled).count
                             + MapLocalEngine.shared.rules.filter(\.isEnabled).count
                Button(ruleCount > 0 ? "Rules (\(ruleCount))" : "Rules",
                       systemImage: "slider.horizontal.3") { showRules = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(store.isRunning ? "Stop" : "Start",
                       systemImage: store.isRunning
                       ? "stop.circle.fill" : "play.circle.fill") {
                    if store.isRunning {
                        BreakpointEngine.shared.dropAll()
                        store.stopProxy()
                    } else {
                        store.startProxy()
                    }
                }
                .tint(store.isRunning ? .red : .green)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", systemImage: "trash") { store.clearAll() }
                    .disabled(store.totalRequestCount == 0)
            }
        }
        .overlay {
            if store.allHosts.isEmpty {
                SidebarEmptyView(store: store)
            }
        }
    }
}
