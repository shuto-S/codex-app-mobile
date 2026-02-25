import SwiftUI

private struct CodexCardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

extension View {
    func codexCardSurface() -> some View {
        self.modifier(CodexCardSurfaceModifier())
    }

    @ViewBuilder
    func codexActionButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
