import XCTest
@testable import CodexAppMobile

final class CodexAppMobileTests: XCTestCase {
    func testHostProfileCodableRoundTrip() throws {
        let profile = SSHHostProfile(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Prod",
            host: "example.com",
            port: 22,
            username: "root"
        )

        let encoded = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([SSHHostProfile].self, from: encoded)

        XCTAssertEqual(decoded, [profile])
    }

    func testHostDraftValidation() {
        let draft = SSHHostDraft(
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
    func testRemoteHostStoreMigratesLegacySSHProfiles() throws {
        let suiteName = "RemoteHostStoreMigration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyProfile = SSHHostProfile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Legacy Host",
            host: "legacy.example.com",
            port: 22,
            username: "legacy-user"
        )
        let encoded = try JSONEncoder().encode([legacyProfile])
        defaults.set(encoded, forKey: "ssh.connection.profiles.v1")

        let credentialStore = InMemoryHostCredentialStore()
        let store = RemoteHostStore(defaults: defaults, credentialStore: credentialStore)

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertEqual(store.hosts[0].id, legacyProfile.id)
        XCTAssertEqual(store.hosts[0].host, legacyProfile.host)
        XCTAssertEqual(store.hosts[0].username, legacyProfile.username)
        XCTAssertEqual(store.hosts[0].appServerURL, "ws://legacy.example.com:8080")
        XCTAssertEqual(store.hosts[0].preferredTransport, .ssh)
    }

    func testRemoteHostDefaultsToSSHTransport() {
        let host = RemoteHost(
            name: "Host A",
            host: "a.example.com",
            sshPort: 22,
            username: "alice",
            appServerURL: "ws://a.example.com:8080"
        )

        XCTAssertEqual(host.preferredTransport, .ssh)
        XCTAssertEqual(RemoteHostDraft.empty.preferredTransport, .ssh)
    }

    func testRemoteHostDecodeLegacyPayloadDefaultsTransportToSSH() throws {
        let payload = """
        {
          "id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "name":"Legacy Host",
          "host":"legacy.example.com",
          "sshPort":22,
          "username":"legacy-user",
          "appServerURL":"ws://legacy.example.com:8080",
          "createdAt":"2026-02-18T00:00:00Z",
          "updatedAt":"2026-02-18T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let host = try decoder.decode(RemoteHost.self, from: Data(payload.utf8))

        XCTAssertEqual(host.preferredTransport, .ssh)
    }

    @MainActor
    func testRemoteHostStoreUpsertUpdatesExistingHost() {
        let suiteName = "RemoteHostStoreUpsert.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let credentialStore = InMemoryHostCredentialStore()
        let store = RemoteHostStore(defaults: defaults, credentialStore: credentialStore)
        store.upsert(
            hostID: nil,
            draft: RemoteHostDraft(
                name: "Host A",
                host: "a.example.com",
                sshPort: 22,
                username: "alice",
                appServerHost: "",
                appServerPort: 8080,
                preferredTransport: .appServerWS,
                password: "old-password"
            )
        )

        guard let hostID = store.hosts.first?.id else {
            XCTFail("Expected a host to be created.")
            return
        }

        store.upsert(
            hostID: hostID,
            draft: RemoteHostDraft(
                name: "Host Z",
                host: "z.example.com",
                sshPort: 2222,
                username: "zack",
                appServerHost: "z.example.com",
                appServerPort: 9000,
                preferredTransport: .ssh,
                password: "new-password"
            )
        )

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertEqual(store.hosts[0].name, "Host Z")
        XCTAssertEqual(store.hosts[0].host, "z.example.com")
        XCTAssertEqual(store.hosts[0].sshPort, 2222)
        XCTAssertEqual(store.hosts[0].username, "zack")
        XCTAssertEqual(store.hosts[0].appServerURL, "ws://z.example.com:9000")
        XCTAssertEqual(store.hosts[0].preferredTransport, .ssh)
        XCTAssertEqual(store.password(for: hostID), "new-password")
    }

    @MainActor
    func testRemoteHostStoreDeleteRemovesHostFromPersistedList() {
        let suiteName = "RemoteHostStoreDelete.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let credentialStore = InMemoryHostCredentialStore()
        let store = RemoteHostStore(defaults: defaults, credentialStore: credentialStore)
        store.upsert(
            hostID: nil,
            draft: RemoteHostDraft(
                name: "Host A",
                host: "a.example.com",
                sshPort: 22,
                username: "alice",
                appServerHost: "",
                appServerPort: 8080,
                preferredTransport: .appServerWS,
                password: ""
            )
        )
        store.upsert(
            hostID: nil,
            draft: RemoteHostDraft(
                name: "Host B",
                host: "b.example.com",
                sshPort: 22,
                username: "bob",
                appServerHost: "",
                appServerPort: 8080,
                preferredTransport: .appServerWS,
                password: ""
            )
        )

        let removedHostID = store.hosts[0].id
        store.delete(hostID: removedHostID)

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertFalse(store.hosts.contains(where: { $0.id == removedHostID }))

        let reloaded = RemoteHostStore(defaults: defaults, credentialStore: credentialStore)
        XCTAssertEqual(reloaded.hosts.count, 1)
        XCTAssertFalse(reloaded.hosts.contains(where: { $0.id == removedHostID }))
    }

    func testProjectWorkspaceDecodesLegacyConnectionID() throws {
        let payload = """
        {
          "id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "connectionID":"11111111-2222-3333-4444-555555555555",
          "name":"workspace",
          "remotePath":"/tmp/project",
          "defaultModel":"",
          "defaultApprovalPolicy":"on-request",
          "createdAt":"2026-02-18T00:00:00Z",
          "updatedAt":"2026-02-18T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workspace = try decoder.decode(ProjectWorkspace.self, from: Data(payload.utf8))
        XCTAssertEqual(workspace.hostID.uuidString.lowercased(), "11111111-2222-3333-4444-555555555555")
    }

    func testThreadSummaryDecodesLegacyConnectionID() throws {
        let payload = """
        {
          "threadID":"thread-1",
          "connectionID":"11111111-2222-3333-4444-555555555555",
          "workspaceID":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "preview":"hello",
          "updatedAt":"2026-02-18T00:00:00Z",
          "archived":false,
          "cwd":"/tmp/project"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(CodexThreadSummary.self, from: Data(payload.utf8))
        XCTAssertEqual(summary.hostID.uuidString.lowercased(), "11111111-2222-3333-4444-555555555555")
    }

    @MainActor
    func testHostSessionStorePersistsSelections() {
        let suiteName = "HostSessionStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let hostID = UUID()
        let projectID = UUID()
        let store = HostSessionStore(defaults: defaults)
        store.upsertSession(hostID: hostID)
        store.selectProject(hostID: hostID, projectID: projectID)
        store.selectThread(hostID: hostID, threadID: "thread-1")

        let reloaded = HostSessionStore(defaults: defaults)
        let session = reloaded.session(for: hostID)
        XCTAssertEqual(session?.selectedProjectID, projectID)
        XCTAssertEqual(session?.selectedThreadID, "thread-1")
    }

    @MainActor
    func testHostSessionStoreCleanupOrphansRemovesInvalidSessions() {
        let suiteName = "HostSessionStoreCleanup.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let validHostID = UUID()
        let orphanHostID = UUID()

        let store = HostSessionStore(defaults: defaults)
        store.upsertSession(hostID: validHostID)
        store.upsertSession(hostID: orphanHostID)
        store.cleanupOrphans(validHostIDs: Set([validHostID]))

        XCTAssertNotNil(store.session(for: validHostID))
        XCTAssertNil(store.session(for: orphanHostID))
    }

    func testTerminalLaunchContextCreatesUniqueIdentifiers() {
        let hostID = UUID()
        let first = TerminalLaunchContext(
            hostID: hostID,
            projectPath: "/tmp/project",
            threadID: "thread-1",
            initialCommand: "codex resume thread-1"
        )
        let second = TerminalLaunchContext(
            hostID: hostID,
            projectPath: "/tmp/project",
            threadID: "thread-1",
            initialCommand: "codex resume thread-1"
        )

        XCTAssertNotEqual(first.id, second.id)
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

    func testJSONRPCEnvelopeDecodesNotificationWithoutJSONRPCHeader() throws {
        let payload = """
        {"method":"item/agentMessage/delta","params":{"threadId":"t1","delta":"hello"}}
        """
        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: Data(payload.utf8))

        XCTAssertNil(envelope.jsonrpc)
        XCTAssertEqual(envelope.method, "item/agentMessage/delta")
        XCTAssertEqual(envelope.params?["threadId"]?.stringValue, "t1")
        XCTAssertEqual(envelope.params?["delta"]?.stringValue, "hello")
    }

    func testJSONRPCEnvelopeEncodeOmitsJSONRPCHeaderByDefault() throws {
        let envelope = JSONRPCEnvelope(
            id: .number(1),
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string("CodexAppMobile"),
                    "version": .string("0.1.0"),
                ])
            ])
        )
        let encoded = try JSONEncoder().encode(envelope)
        let payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertNotNil(payload)
        XCTAssertNil(payload?["jsonrpc"])
        XCTAssertEqual(payload?["method"] as? String, "initialize")
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
    func testAppServerClientResolveAppServerURLKeepsValidInput() throws {
        let resolved = try AppServerClient.resolveAppServerURL(
            raw: "ws://100.103.155.65:8080"
        )
        XCTAssertEqual(resolved.absoluteString, "ws://100.103.155.65:8080")
    }

    @MainActor
    func testAppServerClientResolveAppServerURLRejectsUnroutableHost() {
        XCTAssertThrowsError(
            try AppServerClient.resolveAppServerURL(
                raw: "ws://0.0.0.0:8080"
            )
        ) { error in
            guard case AppServerClientError.invalidEndpointHost(let host) = error else {
                return XCTFail("Expected invalidEndpointHost error.")
            }
            XCTAssertEqual(host, "0.0.0.0")
        }
    }

    @MainActor
    func testAppServerClientResolveAppServerURLRejectsMissingScheme() {
        XCTAssertThrowsError(
            try AppServerClient.resolveAppServerURL(
                raw: "100.103.155.65:8080"
            )
        ) { error in
            guard case AppServerClientError.invalidURL = error else {
                return XCTFail("Expected invalidURL error.")
            }
        }
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

        let invalidHostMessage = client.userFacingMessage(
            for: AppServerClientError.invalidEndpointHost("0.0.0.0")
        )
        XCTAssertTrue(invalidHostMessage.contains("[Connection]"))

        let handshakeMessage = client.userFacingMessage(
            for: URLError(.networkConnectionLost)
        )
        XCTAssertTrue(handshakeMessage.contains("WebSocket handshake failed"))
    }

    @MainActor
    func testAppServerClientUnknownNotificationIsTolerated() {
        let client = AppServerClient()
        client.applyNotificationForTesting(
            method: "item/unknownNotification",
            params: .object(["threadId": .string("thread-1")])
        )

        XCTAssertTrue(client.eventLog.contains("Notification: item/unknownNotification"))
        XCTAssertTrue(client.transcriptByThread.isEmpty)
    }

    @MainActor
    func testAppServerClientNotificationUpdatesTranscriptAndTurnState() {
        let client = AppServerClient()

        client.applyNotificationForTesting(
            method: "item/agentMessage/delta",
            params: .object([
                "threadId": .string("thread-1"),
                "delta": .string("Hello")
            ])
        )
        client.applyNotificationForTesting(
            method: "item/agentMessage/delta",
            params: .object([
                "threadId": .string("thread-1"),
                "delta": .string(" world")
            ])
        )

        client.applyNotificationForTesting(
            method: "turn/started",
            params: .object([
                "threadId": .string("thread-1"),
                "turn": .object([
                    "id": .string("turn-1")
                ])
            ])
        )
        XCTAssertEqual(client.activeTurnID(for: "thread-1"), "turn-1")

        client.applyNotificationForTesting(
            method: "turn/completed",
            params: .object([
                "threadId": .string("thread-1"),
                "turn": .object([
                    "status": .string("completed")
                ])
            ])
        )

        XCTAssertEqual(client.transcriptByThread["thread-1"], "Hello world")
        XCTAssertNil(client.activeTurnID(for: "thread-1"))
    }
}
