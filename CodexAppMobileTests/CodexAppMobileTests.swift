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
            password: "secret"
        )

        XCTAssertTrue(draft.isValid)
    }
}
