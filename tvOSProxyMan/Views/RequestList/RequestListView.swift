import SwiftUI

struct RequestListView: View {
    @Environment(ProxySessionStore.self) private var store

    var body: some View {
        @Bindable var store = store

        List(store.visibleTransactions, selection: $store.selectedTransactionID) { tx in
            RequestRowView(transaction: tx)
                .tag(tx.id)
        }
        .listStyle(.plain)
        .navigationTitle(store.selectedHost ?? "Requests")
        .searchable(text: $store.filterText, prompt: "Filter by path, method, or status")
        .overlay {
            if store.selectedHost == nil {
                ContentUnavailableView(
                    "Select a Host",
                    systemImage: "sidebar.left",
                    description: Text("Choose a host from the sidebar.")
                )
            } else if store.visibleTransactions.isEmpty {
                ContentUnavailableView(
                    store.filterText.isEmpty ? "No Requests" : "No Matches",
                    systemImage: store.filterText.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(store.filterText.isEmpty
                        ? "No traffic captured for this host yet."
                        : "Try a different search term.")
                )
            }
        }
    }
}
