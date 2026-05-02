import SwiftUI

@main
struct tvOSProxyManApp: App {

    init() {
        Task { @MainActor in
            ProxyServer.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
