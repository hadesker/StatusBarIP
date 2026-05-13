import XCTest
@testable import StatusBarIP

final class StatusBarIPTests: XCTestCase {
    func testPublicIPResponseDecoding() throws {
        let json = """
        {
          "ip": "118.71.15.68",
          "real_ip": "118.71.15.68",
          "country": "VN",
          "country_name": "Vietnam",
          "asn": 18403,
          "as_organization": "FPT Telecom",
          "city": "Ho Chi Minh City",
          "timezone": "Asia/Ho_Chi_Minh"
        }
        """

        let response = try JSONDecoder().decode(PublicIPResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.ip, "118.71.15.68")
        XCTAssertEqual(response.realIP, "118.71.15.68")
        XCTAssertEqual(response.countryName, "Vietnam")
        XCTAssertEqual(response.asn, 18403)
        XCTAssertEqual(response.asOrganization, "FPT Telecom")
    }

    func testAdapterClassification() {
        XCTAssertEqual(AdapterClassifier.classify(interfaceName: "tailscale0", address: "100.96.1.2"), .tailscale)
        XCTAssertEqual(AdapterClassifier.classify(interfaceName: "en0", address: "192.168.1.20"), .lan)
        XCTAssertEqual(AdapterClassifier.classify(interfaceName: "utun4", address: "10.10.0.2"), .tunnel)
        XCTAssertEqual(AdapterClassifier.classify(interfaceName: "bridge0", address: "203.0.113.4"), .other)
    }

    func testStatusBarAddressFormatterCanAbbreviateIPAddresses() {
        XCTAssertEqual(
            IPAddressDisplayFormatter.statusBarAddress("111.123.321.22", abbreviated: true),
            "111...22"
        )
        XCTAssertEqual(
            IPAddressDisplayFormatter.statusBarAddress("fe80::10a9:6e2:1256:3dd3", abbreviated: true),
            "fe8...dd3"
        )
        XCTAssertEqual(
            IPAddressDisplayFormatter.statusBarAddress("118.71.15.68", abbreviated: false),
            "118.71.15.68"
        )
        XCTAssertEqual(
            IPAddressDisplayFormatter.statusBarAddress("fe80::10a9:6e2:1256:3dd3", abbreviated: false),
            "fe80...3dd3"
        )
    }

    @MainActor
    func testVisibilityFallbackUsesNextOrderedEntry() {
        let settings = AppSettings(
            fetchInterval: 300,
            orderedIDs: ["lan-en0", AdapterKind.publicIP.rawValue],
            hiddenIDs: ["lan-en0"],
            showDockIcon: false,
            showStatusBarIcon: true,
            abbreviateStatusBarIP: false
        )
        let store = IPStore(
            publicFetcher: MockPublicFetcher(response: PublicIPResponse(ip: "118.71.15.68", realIP: nil, country: nil, countryName: nil, asn: nil, asOrganization: nil, city: nil, timezone: nil)),
            localProvider: MockLocalProvider(entries: [
                IPEntry(id: "lan-en0", kind: .lan, title: "LAN", subtitle: "en0 · IPv4", address: "192.168.1.20", interfaceName: "en0", metadata: nil)
            ]),
            settingsStore: MockSettingsStore(settings: settings),
            networkMonitor: MockNetworkMonitor()
        )

        store.refreshLocalEntries()
        XCTAssertEqual(store.statusEntry?.id, AdapterKind.publicIP.rawValue)
    }
}

private struct MockPublicFetcher: PublicIPFetching {
    let response: PublicIPResponse

    func fetch() async throws -> PublicIPResponse {
        response
    }
}

private struct MockLocalProvider: LocalIPProviding {
    let entries: [IPEntry]

    func currentEntries() -> [IPEntry] {
        entries
    }
}

private final class MockSettingsStore: SettingsStoring {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) {}
}

@MainActor
private final class MockNetworkMonitor: NetworkMonitoring {
    var onStatusChange: ((Bool) -> Void)?

    func start() {}

    func cancel() {}
}
