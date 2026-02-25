import SwiftUI
import UserNotifications

/// Allows notification banners to appear even while the app is in the foreground.
private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct CodexAppMobileApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    private let notificationDelegate = NotificationDelegate()

    init() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        center.delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(self.appState)
                .onAppear {
                    self.installTurnCompletionNotifier()
                }
        }
        .onChange(of: self.scenePhase) {
            switch self.scenePhase {
            case .background:
                self.appState.appServerClient.beginBackgroundProcessingIfNeeded()
            case .active:
                self.appState.appServerClient.endBackgroundProcessing()
            default:
                break
            }
        }
    }

    private func installTurnCompletionNotifier() {
        guard self.appState.appServerClient.onTurnCompleted == nil else { return }

        self.appState.appServerClient.onTurnCompleted = { [weak appState] threadID, _, responseSnippet in
            guard let appState else { return }

            // Skip notification if this thread is currently selected (user is viewing it).
            let isCurrentlyOpen = appState.hostSessionStore.sessions.contains { $0.selectedThreadID == threadID }
            guard !isCurrentlyOpen else { return }

            // Resolve a human-readable title from the thread bookmark.
            let threadTitle: String = {
                if let summary = appState.threadBookmarkStore.bookmarks
                    .first(where: { $0.threadID == threadID }) {
                    let preview = summary.preview.trimmingCharacters(in: .whitespacesAndNewlines)
                    return preview.isEmpty ? "Thread \(threadID.prefix(8))" : preview
                }
                return "Thread \(threadID.prefix(8))"
            }()

            let body = responseSnippet.isEmpty
                ? "Turn completed."
                : Self.stripMarkdown(responseSnippet)

            let content = UNMutableNotificationContent()
            content.title = threadTitle
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "turnCompleted-\(threadID)-\(UUID().uuidString)",
                content: content,
                trigger: nil  // deliver immediately
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Markdown stripping

    /// Remove common Markdown formatting so the notification reads as plain text.
    private static func stripMarkdown(_ text: String) -> String {
        var s = text
        // Fenced code blocks (``` ... ```)
        s = s.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )
        // Inline code
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Bold / italic (*** / ** / * / ___ / __ / _)
        s = s.replacingOccurrences(of: "\\*{1,3}(.+?)\\*{1,3}", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "_{1,3}(.+?)_{1,3}", with: "$1", options: .regularExpression)
        // Strikethrough
        s = s.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)
        // Headers (# ... ######)
        s = s.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        // Links [text](url)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Images ![alt](url)
        s = s.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Bullet / numbered list markers
        s = s.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)
        // Collapse multiple blank lines
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AppRootView: View {
    @State private var isShowingSplash = true
    @State private var iconScale: CGFloat = 0.84
    @State private var iconOpacity = 0.0
    @State private var titleOffset: CGFloat = 10
    @State private var ringScale: CGFloat = 0.92
    @State private var ringOpacity = 0.06

    var body: some View {
        ZStack {
            ContentView()

            if self.isShowingSplash {
                LaunchSplashView(
                    iconScale: self.iconScale,
                    iconOpacity: self.iconOpacity,
                    titleOffset: self.titleOffset,
                    ringScale: self.ringScale,
                    ringOpacity: self.ringOpacity
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task {
            guard self.isShowingSplash else { return }

            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                self.iconScale = 1
                self.iconOpacity = 1
                self.titleOffset = 0
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                self.ringScale = 1.1
                self.ringOpacity = 0.22
            }

            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                self.isShowingSplash = false
            }
        }
    }
}

private struct LaunchSplashView: View {
    let iconScale: CGFloat
    let iconOpacity: Double
    let titleOffset: CGFloat
    let ringScale: CGFloat
    let ringOpacity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.15, blue: 0.24),
                    Color(red: 0.05, green: 0.08, blue: 0.13),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(self.ringOpacity), lineWidth: 2)
                        .frame(width: 90, height: 90)
                        .scaleEffect(self.ringScale)

                    Image("SplashIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .scaleEffect(self.iconScale)
                        .opacity(self.iconOpacity)
                }

                Text("shot star")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(self.iconOpacity))
                    .offset(y: self.titleOffset)
            }
        }
    }
}
