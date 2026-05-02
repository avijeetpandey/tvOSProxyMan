import SwiftUI

@main
struct tvOSProxyManApp: App {

    init() {
        // Register before any URLSession is created so all app-process requests
        // are routed through the interception pipeline.
        URLProtocol.registerClass(ProxyURLProtocol.self)
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
