import XCTest
@testable import CodexAppMobile

final class CodexAppMobileTests: XCTestCase {
    func testConnectionProfileCodableRoundTrip() throws {
        let profile = SSHConnectionProfile(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Prod",
            host: "example.com",
            port: 22,
            username: "root"
        )

        let encoded = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([SSHConnectionProfile].self, from: encoded)

        XCTAssertEqual(decoded, [profile])
    }

    func testConnectionDraftValidation() {
        let draft = SSHConnectionDraft(
            name: "dev",
            host: "127.0.0.1",
            port: 22,
            username: "user",
            password: ""
        )

        XCTAssertTrue(draft.isValid)
    }

    func testHostKeyStoreRoundTrip() {
        let suiteName = "HostKeyStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let endpoint = HostKeyStore.endpointKey(host: "Example.COM", port: 22)
        XCTAssertEqual(endpoint, "example.com:22")
        XCTAssertNil(HostKeyStore.read(for: endpoint, defaults: defaults))

        HostKeyStore.save("ssh-ed25519 AAAATESTKEY", for: endpoint, defaults: defaults)
        XCTAssertEqual(
            HostKeyStore.read(for: endpoint, defaults: defaults),
            "ssh-ed25519 AAAATESTKEY"
        )

        HostKeyStore.remove(for: endpoint, defaults: defaults)
        XCTAssertNil(HostKeyStore.read(for: endpoint, defaults: defaults))
    }
}
