import Foundation
import SwiftUI

enum AdapterKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case publicIP
    case tailscale
    case lan
    case tunnel
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicIP: "Public"
        case .tailscale: "Tailscale"
        case .lan: "LAN"
        case .tunnel: "VPN/Tunnel"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .publicIP: "globe.asia.australia.fill"
        case .tailscale: "point.3.connected.trianglepath.dotted"
        case .lan: "network"
        case .tunnel: "shield.lefthalf.filled"
        case .other: "antenna.radiowaves.left.and.right"
        }
    }

    var tint: Color {
        switch self {
        case .publicIP: .blue
        case .tailscale: .purple
        case .lan: .green
        case .tunnel: .orange
        case .other: .secondary
        }
    }

    static let defaultOrder: [AdapterKind] = [.publicIP, .tailscale, .lan, .tunnel, .other]
}

struct PublicIPResponse: Codable, Equatable, Sendable {
    let ip: String
    let realIP: String?
    let country: String?
    let countryName: String?
    let asn: Int?
    let asOrganization: String?
    let city: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case realIP = "real_ip"
        case country
        case countryName = "country_name"
        case asn
        case asOrganization = "as_organization"
        case city
        case timezone
    }
}

struct IPEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: AdapterKind
    let title: String
    let subtitle: String
    let address: String
    let interfaceName: String?
    let metadata: String?

    var displayTitle: String {
        title.isEmpty ? kind.title : title
    }
}

enum IPAddressDisplayFormatter {
    static func statusBarAddress(_ address: String, abbreviated: Bool) -> String {
        guard abbreviated else { return address }

        if let lastIPv4Part = address.split(separator: ".").last, address.contains(".") {
            return "\(address.prefix(3))...\(lastIPv4Part)"
        }

        guard address.count > 6 else { return address }
        return "\(address.prefix(3))...\(address.suffix(3))"
    }
}

enum AdapterClassifier {
    static func classify(interfaceName: String, address: String) -> AdapterKind {
        let name = interfaceName.lowercased()

        if name.contains("tailscale") || name == "tailscale0" || isTailscaleIPv4(address) {
            return .tailscale
        }

        if name.hasPrefix("utun") || name.hasPrefix("tun") || name.hasPrefix("tap") || name.hasPrefix("ppp") || name.contains("vpn") {
            return .tunnel
        }

        if isPrivateIPv4(address) || address.hasPrefix("fe80:") {
            return .lan
        }

        return .other
    }

    static func isTailscaleIPv4(_ address: String) -> Bool {
        let parts = ipv4Parts(address)
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = ipv4Parts(address)
        guard parts.count == 4 else { return false }

        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        return false
    }

    private static func ipv4Parts(_ address: String) -> [Int] {
        address.split(separator: ".").compactMap { Int($0) }
    }
}
