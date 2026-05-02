import SwiftUI

struct ProxyRulesView: View {
    private enum RulesTab { case breakpoints, mapLocal }
    @State private var activeTab: RulesTab = .breakpoints

    @State private var showAddBreakpoint = false
    @State private var showAddMapLocal   = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TabBarButton(title: "Breakpoints",
                                 icon: "pause.circle",
                                 selected: activeTab == .breakpoints) {
                        activeTab = .breakpoints
                    }
                    TabBarButton(title: "Map Local",
                                 icon: "arrow.left.arrow.right",
                                 selected: activeTab == .mapLocal) {
                        activeTab = .mapLocal
                    }
                }
                .background(.thinMaterial)
                Divider()

                switch activeTab {
                case .breakpoints: BreakpointsListView(showAdd: $showAddBreakpoint)
                case .mapLocal:    MapLocalListView(showAdd: $showAddMapLocal)
                }
            }
            .navigationTitle("Proxy Rules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        if activeTab == .breakpoints { showAddBreakpoint = true }
                        else { showAddMapLocal = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddBreakpoint) { AddBreakpointSheet() }
        .sheet(isPresented: $showAddMapLocal)   { AddMapLocalSheet()   }
    }
}
