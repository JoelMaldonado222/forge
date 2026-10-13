// ForgeTheme.swift — Forge build 2026-10-09 (v7)
// The Volt athletic theme: electric green on dark. Black text goes on top
// of volt; volt text goes on dark surfaces. EVERY color in the app lives
// here, including the UIKit colors the SceneKit body figure needs.
import SwiftUI
import UIKit

enum ForgeTheme {
    // MARK: Volt

    /// Volt's RGB components, shared by SwiftUI and SceneKit so the 3D glow
    /// is always the exact same green as the rest of the app.
    private static let voltR = 0.78
    private static let voltG = 1.0
    private static let voltB = 0.02

    /// Electric volt green — the app's signature accent.
    static let volt = Color(red: voltR, green: voltG, blue: voltB)

    /// Soft volt wash for glows, track backgrounds, and highlights.
    static let voltWash = volt.opacity(0.16)

    /// Volt → mint gradient for hero numbers and dynamic accents.
    static let voltGradient = LinearGradient(
        colors: [volt, Color(red: 0.32, green: 1.0, blue: 0.55)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Surfaces

    /// Background for cards, tiles, and logging rows.
    static let card = Color(.secondarySystemBackground)

    /// Empty bar / unfilled track.
    static let track = Color.gray.opacity(0.25)

    // MARK: Status

    /// Positive confirmation ("Saved.", selected checkmarks).
    static let success = volt
    /// Errors, destructive actions, validation messages.
    static let danger = Color.red
    /// Insight tone: something worth a look.
    static let warning = Color.orange
    /// Insight tone: neutral information.
    static let info = Color.blue

    // MARK: 3D figure (SceneKit needs UIColor)

    static let sceneBackground = UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0)
    /// Graphite base body (head, joints, limb cores), so volt is THE color
    /// on the figure.
    static let figureNeutral = UIColor(red: 0.36, green: 0.38, blue: 0.43, alpha: 1.0)
    static let figureNeutralSpecular = UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 1.0)
    /// Untrained muscles: a shade lighter than the base so their shapes
    /// still read when nothing is lit.
    private static let figureMuscleRGB = (r: 0.44, g: 0.46, b: 0.52)
    static let figureMuscleSpecular = UIColor(red: 0.28, green: 0.30, blue: 0.33, alpha: 1.0)
    /// Soft contact shadow under the feet.
    static let figureGroundShadow = UIColor(white: 0.0, alpha: 0.35)
    /// Lights for the figure: cool ambient, warm key, soft fill, blue-white rim.
    static let figureAmbientLight = UIColor(red: 0.55, green: 0.58, blue: 0.65, alpha: 1.0)
    static let figureKeyLight = UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0)
    static let figureFillLight = UIColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1.0)
    static let figureRimLight = UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1.0)

    /// How strongly a muscle shows volt for a 0...1 training intensity.
    /// Anything trained starts at 45% so light work still reads as volt
    /// (not a muddy olive); the hardest-worked muscle is full strength.
    static func figureGlowLevel(_ intensity: Double) -> Double {
        let raw = min(max(intensity, 0), 1)
        return raw > 0 ? 0.45 + 0.55 * raw : 0
    }

    /// A muscle's surface color: its grey, blended toward volt as it glows.
    static func figureMuscleColor(_ intensity: Double) -> UIColor {
        let mix = 0.8 * figureGlowLevel(intensity)
        let base = figureMuscleRGB
        return UIColor(
            red: base.r + (voltR - base.r) * mix,
            green: base.g + (voltG - base.g) * mix,
            blue: base.b + (voltB - base.b) * mix,
            alpha: 1.0
        )
    }

    /// A muscle's self-lit glow for a 0...1 intensity (black = no glow).
    static func voltGlow(_ intensity: Double) -> UIColor {
        let i = 0.55 * figureGlowLevel(intensity)
        return UIColor(red: voltR * i, green: voltG * i, blue: voltB * i, alpha: 1.0)
    }
}

/// Primary call-to-action: volt pill, black bold text. Replaces
/// `.borderedProminent` everywhere it was used.
struct VoltButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(ForgeTheme.volt.opacity(configuration.isPressed ? 0.65 : (isEnabled ? 1.0 : 0.35)))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Rounded card surface used across Today, Workout, and History.
struct ForgeCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding()
            .background(ForgeTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Pads the content and puts it on a rounded card surface.
    func forgeCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(ForgeCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Typed-number parsing

/// One place for turning text-field input into numbers, so every screen
/// handles the same edge cases the same way.
enum ForgeInput {
    /// Parses a decimal the user typed. Accepts "." or "," as the decimal
    /// separator (the decimal pad shows "," in some regions). Returns nil
    /// for blank or malformed input like "185.5.5".
    static func decimal(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// Parses a whole number (reps, age). Returns nil for blank or malformed input.
    static func whole(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// True when the field is empty or only spaces.
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "185" or "185.5" — compact display for a stored number.
    static func display(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
