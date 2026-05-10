import Darwin
import Foundation

protocol LocalIPProviding {
    func currentEntries() -> [IPEntry]
}

struct LocalIPService: LocalIPProviding {
    func currentEntries() -> [IPEntry] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var entries: [IPEntry] = []
        var idCounts: [String: Int] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }

            guard (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let addressPointer = interface.ifa_addr else {
                continue
            }

            let family = addressPointer.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else {
                continue
            }

            let interfaceName = String(cString: interface.ifa_name)
            guard let address = stringAddress(from: addressPointer), shouldDisplay(address: address) else {
                continue
            }

            let kind = AdapterClassifier.classify(interfaceName: interfaceName, address: address)
            let familyLabel = family == UInt8(AF_INET) ? "IPv4" : "IPv6"
            let baseID = "\(interfaceName)-\(familyLabel.lowercased())"
            let count = idCounts[baseID, default: 0]
            idCounts[baseID] = count + 1
            let stableID = count == 0 ? baseID : "\(baseID)-\(count + 1)"
            entries.append(
                IPEntry(
                    id: stableID,
                    kind: kind,
                    title: kind.title,
                    subtitle: "\(interfaceName) · \(familyLabel)",
                    address: address,
                    interfaceName: interfaceName,
                    metadata: nil
                )
            )
        }

        return entries
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return AdapterKind.defaultOrder.firstIndex(of: lhs.kind) ?? 99 < AdapterKind.defaultOrder.firstIndex(of: rhs.kind) ?? 99
                }
                if lhs.interfaceName != rhs.interfaceName {
                    return (lhs.interfaceName ?? "") < (rhs.interfaceName ?? "")
                }
                return lhs.address < rhs.address
            }
    }

    private func stringAddress(from pointer: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length: socklen_t

        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
            length = socklen_t(MemoryLayout<sockaddr_in>.size)
        case AF_INET6:
            length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        default:
            return nil
        }

        let result = getnameinfo(pointer, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        let endIndex = host.firstIndex(of: 0) ?? host.endIndex
        return String(decoding: host[..<endIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func shouldDisplay(address: String) -> Bool {
        if address == "0.0.0.0" || address == "::1" || address == "127.0.0.1" {
            return false
        }
        return !address.isEmpty
    }
}
