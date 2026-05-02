import SwiftUI

struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportState: ExportState = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    stepCard(
                        number: "1",
                        title: "Configure This Apple TV as Its Own Proxy",
                        icon: "network"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            instructionRow("Open the tvOS Settings app.")
                            instructionRow("Navigate to Network → Wi-Fi → [your network].")
                            instructionRow("Scroll down and tap Configure Proxy.")
                            instructionRow("Select Manual.")
                            instructionRow("Set Server to 127.0.0.1 and Port to 9090.")
                            instructionRow("Leave Authentication off. Tap Done.")

                            Divider().padding(.vertical, 4)

                            Label("The proxy must be running before you set this.", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    stepCard(
                        number: "2",
                        title: "Export the Root CA Certificate",
                        icon: "lock.shield"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("The proxy generates a self-signed Root CA on first launch. Client devices (and this Apple TV) must trust it to avoid TLS errors.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button(action: exportRootCA) {
                                Label("Export Root CA to Documents", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)

                            switch exportState {
                            case .idle:
                                EmptyView()
                            case .success(let path):
                                Label("Saved to:\n\(path)", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .fixedSize(horizontal: false, vertical: true)
                                Label("Base64 and file path also printed to Xcode console.", systemImage: "terminal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .unavailable:
                                Label("Root CA not ready — start the proxy first.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            case .failed(let msg):
                                Label("Export failed: \(msg)", systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    stepCard(
                        number: "3",
                        title: "Install Root CA via Apple Configurator",
                        icon: "desktopcomputer"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            instructionRow("On your Mac, open Apple Configurator 2 (free on the Mac App Store).")
                            instructionRow("Connect the Apple TV to your Mac via USB-C.")
                            instructionRow("Select this device in Apple Configurator.")
                            instructionRow("Drag and drop the exported tvOSProxyMan-RootCA.cer file onto the device.")
                            instructionRow("Follow the on-screen prompts to install and trust the certificate profile.")

                            Divider().padding(.vertical, 4)

                            Label("The .cer file is in the app's Documents folder. Retrieve it via Xcode → Window → Devices and Simulators → Download Container, or copy it from the path shown in Step 2.", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    stepCard(
                        number: "4",
                        title: "Trust the Certificate (iOS / macOS Clients)",
                        icon: "checkmark.shield"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("iOS / iPadOS")
                                .font(.headline)
                            instructionRow("Settings → General → VPN & Device Management → tap the tvOSProxyMan profile → Install.")
                            instructionRow("Settings → General → About → Certificate Trust Settings → enable full trust.")

                            Divider().padding(.vertical, 4)

                            Text("macOS")
                                .font(.headline)
                            instructionRow("Double-click the .cer file to add it to Keychain Access.")
                            instructionRow("Open Keychain Access, find tvOSProxyMan Root CA, double-click → Trust → Always Trust.")
                        }
                    }
                }
                .padding(48)
            }
            .navigationTitle("Local Device Setup")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Root CA export

    private func exportRootCA() {
        guard let der = CertificateManager.shared.rootCACertificateDER else {
            exportState = .unavailable
            return
        }

        let fileName = "tvOSProxyMan-RootCA.cer"
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first else {
            exportState = .failed("Cannot locate Documents directory.")
            return
        }
        let dest = docs.appendingPathComponent(fileName)
        do {
            try der.write(to: dest, options: .atomic)
            let path = dest.path
            exportState = .success(path: path)

            // Print to Xcode console so the developer can retrieve it easily.
            print("[tvOSProxyMan] Root CA saved to: \(path)")
            print("[tvOSProxyMan] Root CA Base64 (paste into a .cer file if needed):")
            print(der.base64EncodedString(options: .lineLength64Characters))
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepCard(
        number: String,
        title: String,
        icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                    Text(number)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                Label(title, systemImage: icon)
                    .font(.title3.bold())
            }

            content()
                .padding(.leading, 60)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func instructionRow(_ text: String) -> some View {
        Label(text, systemImage: "chevron.right")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Export state

    private enum ExportState {
        case idle
        case success(path: String)
        case unavailable
        case failed(String)
    }
}
