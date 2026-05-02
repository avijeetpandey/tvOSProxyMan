import SwiftUI

struct TransactionDetailView: View {
    @Environment(ProxySessionStore.self) private var store

    private enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case request  = "Request"
        case response = "Response"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .request:  return "arrow.up.circle"
            case .response: return "arrow.down.circle"
            }
        }
    }

    @State private var selectedTab: DetailTab = .overview
    @FocusState private var focusedTab: DetailTab?

    var body: some View {
        guard let tx = store.selectedTransaction else {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(DetailTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .font(.headline)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                                .background(selectedTab == tab
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear)
                                .foregroundStyle(selectedTab == tab
                                                 ? .primary : .secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focused($focusedTab, equals: tab)
                    }
                }
                .background(.thinMaterial)

                Divider()

                ScrollView {
                    switch selectedTab {
                    case .overview: OverviewTab(tx: tx)
                    case .request:  RequestTab(tx: tx)
                    case .response: ResponseTab(tx: tx)
                    }
                }
            }
            .navigationTitle(tx.host)
        )
    }
}
