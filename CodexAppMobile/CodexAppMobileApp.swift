import SwiftUI

@main
struct CodexAppMobileApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(self.appState)
        }
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

                    Image(systemName: "terminal.fill")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.16))
                        )
                        .scaleEffect(self.iconScale)
                        .opacity(self.iconOpacity)
                }

                Text("Codex Mobile")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(self.iconOpacity))
                    .offset(y: self.titleOffset)
            }
        }
    }
}
