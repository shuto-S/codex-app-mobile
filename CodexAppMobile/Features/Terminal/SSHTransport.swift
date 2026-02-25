import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import NIOTransportServices

final class SSHClientEngine: @unchecked Sendable {
    enum EngineError: Error {
        case missingSSHHandler
        case missingSessionChannel
        case invalidChannelType
        case notConnected
    }

    var onOutput: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private var eventLoopGroup: NIOTSEventLoopGroup?
    private var rootChannel: Channel?
    private var sessionChannel: Channel?

    func connect(host: String, port: Int, username: String, password: String?) throws {
        self.disconnect()

        let group = NIOTSEventLoopGroup()
        self.eventLoopGroup = group
        let endpoint = HostKeyStore.endpointKey(host: host, port: port)
        let onOutput = self.onOutput
        let onDisconnected = self.onDisconnected
        let onError = self.onError

        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    let userAuthDelegate = OptionalPasswordAuthenticationDelegate(username: username, password: password)
                    let hostKeyDelegate = TrustOnFirstUseHostKeysDelegate(endpoint: endpoint)
                    let sshHandler = NIOSSHHandler(
                        role: .client(
                            .init(
                                userAuthDelegate: userAuthDelegate,
                                serverAuthDelegate: hostKeyDelegate
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )

                    try sync.addHandler(sshHandler)
                    try sync.addHandler(RootErrorHandler { error in
                        onError?(error)
                    })
                }
            }

        do {
            let root = try bootstrap.connect(host: host, port: port).wait()
            self.rootChannel = root

            let sessionChannelFuture = root.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
                let childChannelPromise = root.eventLoop.makePromise(of: Channel.self)

                sshHandler.createChannel(childChannelPromise, channelType: .session) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(EngineError.invalidChannelType)
                    }

                    let handler = SessionOutputHandler(
                        onOutput: { text in
                            onOutput?(text)
                        },
                        onClosed: {
                            onDisconnected?()
                        },
                        onError: { error in
                            onError?(error)
                        }
                    )
                    return childChannel.pipeline.addHandler(handler)
                }

                return childChannelPromise.futureResult
            }

            self.sessionChannel = try sessionChannelFuture.wait()
            self.onConnected?()
        } catch {
            self.disconnect()
            throw error
        }
    }

    func send(command: String) throws {
        guard let sessionChannel = self.sessionChannel else {
            throw EngineError.notConnected
        }

        var buffer = sessionChannel.allocator.buffer(capacity: command.utf8.count)
        buffer.writeString(command)

        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        sessionChannel.writeAndFlush(data, promise: nil)
    }

    func disconnect() {
        self.sessionChannel?.close(promise: nil)
        self.sessionChannel = nil

        self.rootChannel?.close(promise: nil)
        self.rootChannel = nil

        if let eventLoopGroup = self.eventLoopGroup {
            self.eventLoopGroup = nil
            try? eventLoopGroup.syncShutdownGracefully()
        }

        self.onDisconnected?()
    }
}

final class SessionOutputHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let onOutput: (String) -> Void
    private let onClosed: () -> Void
    private let onError: (Error) -> Void
    private var pendingUTF8Data = Data()
    private var terminalQueryResponder = TerminalQueryResponder()

    init(
        onOutput: @escaping (String) -> Void,
        onClosed: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onOutput = onOutput
        self.onClosed = onClosed
        self.onError = onError
    }

    func channelActive(context: ChannelHandlerContext) {
        let langRequest = SSHChannelRequestEvent.EnvironmentRequest(
            wantReply: false,
            name: "LANG",
            value: "en_US.UTF-8"
        )
        let lcCTypeRequest = SSHChannelRequestEvent.EnvironmentRequest(
            wantReply: false,
            name: "LC_CTYPE",
            value: "en_US.UTF-8"
        )
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: false,
            term: "xterm-256color",
            terminalCharacterWidth: 120,
            terminalRowHeight: 40,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        context.triggerUserOutboundEvent(langRequest, promise: nil)
        context.triggerUserOutboundEvent(lcCTypeRequest, promise: nil)
        context.triggerUserOutboundEvent(ptyRequest, promise: nil)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: false), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)

        guard case .byteBuffer(var buffer) = channelData.data else {
            return
        }

        let readableBytes = buffer.readableBytes
        guard readableBytes > 0,
              let chunk = buffer.readBytes(length: readableBytes)
        else {
            return
        }

        self.pendingUTF8Data.append(contentsOf: chunk)
        self.flushUTF8Buffer(context: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let exitStatus = event as? SSHChannelRequestEvent.ExitStatus {
            self.onOutput("\n[remote exit status: \(exitStatus.exitStatus)]\n")
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.flushRemainingUTF8BufferLossy(context: nil)
        self.onClosed()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error)
        context.close(promise: nil)
    }

    private func flushUTF8Buffer(context: ChannelHandlerContext?) {
        while !self.pendingUTF8Data.isEmpty {
            if let text = String(data: self.pendingUTF8Data, encoding: .utf8) {
                self.emitRaw(text, context: context)
                self.pendingUTF8Data.removeAll(keepingCapacity: true)
                return
            }

            let prefixLength = self.longestValidUTF8PrefixLength(in: self.pendingUTF8Data)
            if prefixLength > 0,
               let text = String(data: self.pendingUTF8Data.prefix(prefixLength), encoding: .utf8) {
                self.emitRaw(text, context: context)
                self.pendingUTF8Data.removeFirst(prefixLength)
                continue
            }

            // UTF-8 uses up to 4 bytes, so wait for the next chunk when 4 bytes or less remain.
            if self.pendingUTF8Data.count <= 4 {
                return
            }

            let fallback = String(decoding: self.pendingUTF8Data.prefix(1), as: UTF8.self)
            self.emitRaw(fallback, context: context)
            self.pendingUTF8Data.removeFirst()
        }
    }

    private func flushRemainingUTF8BufferLossy(context: ChannelHandlerContext?) {
        guard !self.pendingUTF8Data.isEmpty else { return }
        let remaining = String(decoding: self.pendingUTF8Data, as: UTF8.self)
        self.emitRaw(remaining, context: context)
        self.pendingUTF8Data.removeAll(keepingCapacity: true)
    }

    private func longestValidUTF8PrefixLength(in data: Data) -> Int {
        var low = 1
        var high = data.count
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            if String(data: data.prefix(mid), encoding: .utf8) != nil {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }

    private func emitRaw(_ text: String, context: ChannelHandlerContext?) {
        guard !text.isEmpty else { return }
        if let context {
            let responses = self.terminalQueryResponder.process(text)
            for response in responses {
                self.sendTerminalResponse(response, context: context)
            }
        } else {
            _ = self.terminalQueryResponder.process(text)
        }
        self.onOutput(text)
    }

    private func sendTerminalResponse(_ response: String, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: response.utf8.count)
        buffer.writeString(response)
        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.channel.writeAndFlush(data, promise: nil)
    }
}

private struct TerminalQueryResponder {
    private enum State {
        case plain
        case esc
        case csi
    }

    private var state: State = .plain
    private var parameters = ""
    private var intermediates = ""

    mutating func process(_ input: String) -> [String] {
        var responses: [String] = []

        for scalar in input.unicodeScalars {
            let value = scalar.value

            switch self.state {
            case .plain:
                if value == 0x1B {
                    self.state = .esc
                    continue
                }
                if value == 0x9B {
                    self.beginCSI()
                    continue
                }

            case .esc:
                if scalar == "[" {
                    self.beginCSI()
                } else {
                    self.state = .plain
                }

            case .csi:
                if (0x30...0x3F).contains(value) {
                    self.parameters.unicodeScalars.append(scalar)
                } else if (0x20...0x2F).contains(value) {
                    self.intermediates.unicodeScalars.append(scalar)
                } else if (0x40...0x7E).contains(value) {
                    if let response = self.response(final: scalar) {
                        responses.append(response)
                    }
                    self.state = .plain
                } else if value == 0x1B {
                    self.state = .esc
                }
            }
        }

        return responses
    }

    private mutating func beginCSI() {
        self.parameters = ""
        self.intermediates = ""
        self.state = .csi
    }

    private func response(final: UnicodeScalar) -> String? {
        switch final {
        case "c":
            if self.intermediates == ">" {
                // Secondary Device Attributes response (xterm compatible)
                return "\u{1B}[>0;10;1c"
            }
            // Primary Device Attributes response (VT100 with advanced video option)
            if self.parameters.isEmpty || self.parameters == "0" {
                return "\u{1B}[?1;2c"
            }
            return nil

        case "n":
            let normalized = self.parameters.replacingOccurrences(of: "?", with: "")
            if normalized == "5" {
                // Device Status Report: "OK"
                return "\u{1B}[0n"
            }
            if normalized == "6" {
                // Cursor position report (home position as minimal fallback)
                return "\u{1B}[1;1R"
            }
            return nil

        default:
            return nil
        }
    }
}

final class RootErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let onError: (Error) -> Void

    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error)
        context.close(promise: nil)
    }
}

enum SSHConnectionErrorFormatter {
    static func message(for error: Error, endpoint: String) -> String {
        if let validationError = error as? HostKeyValidationError {
            return validationError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           let posixCode = POSIXErrorCode(rawValue: Int32(nsError.code)) {
            switch posixCode {
            case .ECONNREFUSED:
                return "Connection refused by \(endpoint). Ensure SSH server is running on the target host."
            case .ETIMEDOUT:
                return "Connection timed out for \(endpoint). Check VPN/Tailscale or network reachability."
            case .EHOSTUNREACH, .ENETUNREACH:
                return "Network is unreachable for \(endpoint)."
            default:
                break
            }
        }

        let description = nsError.localizedDescription
        let lowercased = description.lowercased()
        if lowercased.contains("permission denied")
            || lowercased.contains("authentication failed")
            || lowercased.contains("unable to authenticate") {
            return "Authentication failed for \(endpoint). Check username/password or server auth settings."
        }
        if lowercased.contains("host key") && lowercased.contains("mismatch") {
            return "Host key mismatch for \(endpoint). Re-register the host key only if rotation is intentional."
        }
        if lowercased.contains("timed out") {
            return "Connection timed out for \(endpoint)."
        }

        return "Connection failed for \(endpoint): \(description)"
    }
}

enum HostKeyValidationError: LocalizedError {
    case changedHostKey(endpoint: String)

    var errorDescription: String? {
        switch self {
        case .changedHostKey(let endpoint):
            return "Host key mismatch for \(endpoint). Remove the saved host key only if the server key rotation is intentional."
        }
    }
}

final class TrustOnFirstUseHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let endpoint: String

    init(endpoint: String) {
        self.endpoint = endpoint
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presentedHostKey = String(openSSHPublicKey: hostKey)

        if let trustedHostKey = HostKeyStore.read(for: self.endpoint) {
            if trustedHostKey == presentedHostKey {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyValidationError.changedHostKey(endpoint: self.endpoint))
            }
            return
        }

        HostKeyStore.save(presentedHostKey, for: self.endpoint)
        validationCompletePromise.succeed(())
    }
}

public final class OptionalPasswordAuthenticationDelegate {
    private enum State {
        case tryNone
        case tryPassword
        case done
    }

    private var state: State = .tryNone
    private let username: String
    private let password: String?

    init(username: String, password: String?) {
        self.username = username
        self.password = password
    }
}

@available(*, unavailable)
extension OptionalPasswordAuthenticationDelegate: Sendable {}

extension OptionalPasswordAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate {
    public func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch self.state {
        case .tryNone:
            self.state = .tryPassword
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: self.username,
                    serviceName: "",
                    offer: .none
                )
            )
        case .tryPassword:
            self.state = .done
            guard let password = self.password, availableMethods.contains(.password) else {
                nextChallengePromise.succeed(nil)
                return
            }
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: self.username,
                    serviceName: "",
                    offer: .password(.init(password: password))
                )
            )
        case .done:
            nextChallengePromise.succeed(nil)
        }
    }
}
