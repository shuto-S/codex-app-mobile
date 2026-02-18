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

    func testHostKeyStoreAllReturnsSortedEndpoints() {
        let suiteName = "HostKeyStoreAllTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        HostKeyStore.save("ssh-ed25519 KEY_A", for: "z.example.com:22", defaults: defaults)
        HostKeyStore.save("ssh-ed25519 KEY_B", for: "a.example.com:22", defaults: defaults)

        let endpoints = HostKeyStore.all(defaults: defaults).map(\.endpoint)
        XCTAssertEqual(endpoints, ["a.example.com:22", "z.example.com:22"])
    }

    func testSSHConnectionErrorFormatterClassifiesConnectionRefused() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ECONNREFUSED.rawValue))
        let message = SSHConnectionErrorFormatter.message(for: error, endpoint: "host:22")
        XCTAssertTrue(message.contains("Connection refused"))
        XCTAssertTrue(message.contains("host:22"))
    }

    @MainActor
    func testRemoteConnectionStoreMigratesLegacySSHProfiles() throws {
        let suiteName = "RemoteConnectionStoreMigration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyProfile = SSHConnectionProfile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Legacy Host",
            host: "legacy.example.com",
            port: 22,
            username: "legacy-user"
        )
        let encoded = try JSONEncoder().encode([legacyProfile])
        defaults.set(encoded, forKey: "ssh.connection.profiles.v1")

        let credentialStore = InMemoryConnectionCredentialStore()
        let store = RemoteConnectionStore(defaults: defaults, credentialStore: credentialStore)

        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.connections[0].id, legacyProfile.id)
        XCTAssertEqual(store.connections[0].host, legacyProfile.host)
        XCTAssertEqual(store.connections[0].username, legacyProfile.username)
        XCTAssertEqual(store.connections[0].appServerURL, "ws://legacy.example.com:8080")
    }

    func testJSONRPCEnvelopeDecodesNotification() throws {
        let payload = """
        {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"t1","turnId":"u1","itemId":"i1","delta":"hello"}}
        """
        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: Data(payload.utf8))

        XCTAssertEqual(envelope.method, "item/agentMessage/delta")
        XCTAssertNil(envelope.id)
        XCTAssertEqual(envelope.params?["threadId"]?.stringValue, "t1")
        XCTAssertEqual(envelope.params?["delta"]?.stringValue, "hello")
    }

    func testAppServerMessageRouterResolvesResponse() async throws {
        let router = AppServerMessageRouter()
        let requestID = await router.makeRequestID()

        let valueTask = Task<JSONValue, Error> {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await router.storeContinuation(continuation, for: String(requestID))
                }
            }
        }

        await Task.yield()
        await router.resolveResponse(
            id: .number(Double(requestID)),
            result: .object(["ok": .bool(true)]),
            error: nil
        )

        let value = try await valueTask.value
        XCTAssertEqual(value["ok"]?.boolValue, true)
    }

    @MainActor
    func testAppServerClientVersionCompatibility() {
        XCTAssertTrue(AppServerClient.isVersion("0.101.0", atLeast: "0.101.0"))
        XCTAssertTrue(AppServerClient.isVersion("0.101.1", atLeast: "0.101.0"))
        XCTAssertTrue(AppServerClient.isVersion("v0.102.0-beta.1", atLeast: "0.101.0"))
        XCTAssertFalse(AppServerClient.isVersion("0.100.9", atLeast: "0.101.0"))
    }

    @MainActor
    func testAppServerClientUserFacingMessageCategories() {
        let client = AppServerClient()

        let compatibilityMessage = client.userFacingMessage(
            for: AppServerClientError.incompatibleVersion(current: "0.100.0", minimum: "0.101.0")
        )
        XCTAssertTrue(compatibilityMessage.contains("[Compatibility]"))

        let connectionMessage = client.userFacingMessage(
            for: AppServerClientError.timeout(method: "thread/list")
        )
        XCTAssertTrue(connectionMessage.contains("[Connection]"))
    }
}
