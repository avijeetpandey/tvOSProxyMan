import SwiftUI

struct MapLocalListView: View {
    @Binding var showAdd: Bool

    var body: some View {
        let engine = MapLocalEngine.shared
        if engine.rules.isEmpty {
            ContentUnavailableView(
                "No Map Local Rules",
                systemImage: "arrow.left.arrow.right",
                description: Text("Tap + to add a URL pattern.\nMatching requests return your local JSON immediately.")
            )
        } else {
            List {
                ForEach(engine.rules) { rule in
                    MapLocalRowView(rule: rule)
                }
                .onDelete { offsets in
                    offsets.forEach { engine.removeRule(id: engine.rules[$0].id) }
                }
            }
            .listStyle(.grouped)
        }
    }
}
