import Foundation
@preconcurrency import Network

@MainActor
protocol NetworkMonitoring: AnyObject {
    var onStatusChange: ((Bool) -> Void)? { get set }

    func start()
    func cancel()
}

@MainActor
final class NetworkMonitorService: NetworkMonitoring {
    var onStatusChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.hadesker.statusbarip.network-monitor")
    private var lastConnectionState: Bool?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied

            Task { @MainActor in
                guard self?.lastConnectionState != isConnected else { return }
                self?.lastConnectionState = isConnected
                self?.onStatusChange?(isConnected)
            }
        }

        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
