// ForgeTheme.swift — Forge build 2026-10-06
// The Volt athletic theme: electric green on dark. Black text goes on top
// of volt; volt text goes on dark surfaces.
import SwiftUI

enum ForgeTheme {
    /// Electric volt green — the app's signature accent.
    static let volt = Color(red: 0.78, green: 1.0, blue: 0.02)

    /// Soft volt wash for glows, track backgrounds, and highlights.
    static let voltWash = volt.opacity(0.16)

    /// Volt → mint gradient for hero numbers and dynamic accents.
    static let voltGradient = LinearGradient(
        colors: [volt, Color(red: 0.32, green: 1.0, blue: 0.55)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Primary call-to-action: volt pill, black bold text. Replaces
/// `.borderedProminent` everywhere it was used.
struct VoltButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(ForgeTheme.volt.opacity(configuration.isPressed ? 0.65 : 1.0))
            .clipShape(Capsule())
    }
}
