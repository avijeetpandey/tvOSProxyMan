import SwiftUI

struct ContentView: View {
    @State private var store = ProxySessionStore()
    @State private var showRules = false

    private var hasPausedRequest: Bool {
        !BreakpointEngine.shared.pausedRequests.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            HostSidebarView(showRules: $showRules)
        } content: {
            RequestListView()
        } detail: {
            if store.selectedTransaction != nil {
                TransactionDetailView()
            } else {
                EmptyDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(store)
        .sheet(isPresented: $showRules) { ProxyRulesView() }
        .fullScreenCover(isPresented: Binding(
            get: { hasPausedRequest },
            set: { _ in }
        )) {
            if let req = BreakpointEngine.shared.pausedRequests.first {
                BreakpointModalView(requestID: req.id)
            }
        }
    }
}
