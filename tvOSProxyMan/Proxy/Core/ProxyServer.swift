import Foundation
import Network
import os.log

@MainActor
@Observable
final class ProxyServer {
    static let shared = ProxyServer()

    private(set) var isRunning = false
    private(set) var listeningPort: UInt16 = 9090
    private(set) var transactions: [ProxyTransaction] = []
    private(set) var activeConnectionCount = 0
    private(set) var lastError: String?

    private var listener: NWListener?
    private var connections: [UUID: ProxyConnection] = [:]
    private let networkQueue = DispatchQueue(
        label: "com.tvOSProxyMan.network",
        qos: .userInitiated
    )
    private let logger = Logger(subsystem: "com.tvOSProxyMan", category: "ProxyServer")

    private init() {}

    // MARK: - Lifecycle

    func start(on port: UInt16 = 9090) {
        guard !isRunning else { return }
        listeningPort = port

        Task.detached(priority: .userInitiated) {
            do {
                try CertificateManager.shared.initialize()
            } catch {
                await MainActor.run { }
            }
        }

        // NWParameters.tcp with no requiredInterfaceType binds to all interfaces,
        // including the loopback interface (127.0.0.1 / ::1). This lets the device
        // proxy its own traffic by setting its Wi-Fi proxy to 127.0.0.1:9090.
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port: \(port)"
            return
        }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            lastError = error.localizedDescription
            logger.error("Listener creation failed: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.lastError = nil
                    self.logger.info("Proxy ready on port \(self.listeningPort)")
                case .failed(let error):
                    self.isRunning = false
                    self.lastError = error.localizedDescription
                    self.listener = nil
                    self.logger.error("Listener failed: \(error)")
                case .cancelled:
                    self.isRunning = false
                case .waiting(let error):
                    self.lastError = "Waiting: \(error.localizedDescription)"
                default:
                    break
                }
            }
        }

        let queue = networkQueue
        // Capture the port as a plain value so the nonisolated newConnectionHandler
        // can pass it to ProxyConnection without touching the @MainActor property.
        let capturedPort = port
        listener?.newConnectionHandler = { [weak self] nwConnection in
            guard let self else { return }
            let conn = ProxyConnection(nwConnection: nwConnection, server: self,
                                       proxyPort: capturedPort)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connections[conn.id] = conn
                self.activeConnectionCount = self.connections.count
            }
            conn.start(on: queue)
        }

        listener?.start(queue: networkQueue)
        logger.info("Starting proxy on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        activeConnectionCount = 0
        isRunning = false
    }

    func clearTransactions() {
        transactions.removeAll()
    }

    // MARK: - nonisolated entry points (called from ProxyConnection on network queue)

    nonisolated func capture(_ transaction: ProxyTransaction) {
        Task { @MainActor [weak self] in
            self?.transactions.append(transaction)
        }
    }

    nonisolated func updateTransaction(
        id: UUID,
        state: TransactionState,
        responseStatusCode: Int? = nil,
        responseStatusMessage: String? = nil,
        responseHeaders: [HTTPHeaderField] = [],
        responseBody: Data? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  let idx = self.transactions.firstIndex(where: { $0.id == id })
            else { return }

            self.transactions[idx].state = state
            if let code = responseStatusCode {
                self.transactions[idx].responseStatusCode = code
            }
            if let msg = responseStatusMessage {
                self.transactions[idx].responseStatusMessage = msg
            }
            if !responseHeaders.isEmpty {
                self.transactions[idx].responseHeaders = responseHeaders
            }
            if let body = responseBody {
                self.transactions[idx].responseBody = body
            }
            switch state {
            case .complete, .failed:
                self.transactions[idx].endTime = Date()
            default:
                break
            }
        }
    }

    nonisolated func connectionDidClose(_ id: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connections.removeValue(forKey: id)
            self.activeConnectionCount = self.connections.count
        }
    }
}
