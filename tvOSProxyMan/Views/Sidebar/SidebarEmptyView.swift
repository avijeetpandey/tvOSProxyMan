import SwiftUI

struct SidebarEmptyView: View {
    let store: ProxySessionStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: store.isRunning
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 64))
                .foregroundStyle(store.isRunning ? .green : .secondary)
                .symbolEffect(.pulse, isActive: store.isRunning)

            if store.isRunning {
                VStack(spacing: 8) {
                    Text("Proxy listening on :\(store.listeningPort, format: .number.grouping(.never))")
                        .font(.headline)
                    Text("Configure your device to use this\nApple TV as its HTTP proxy.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if let err = store.lastError {
                Text(err).foregroundStyle(.red).font(.subheadline)
            } else {
                Text("Proxy stopped").foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }
}
