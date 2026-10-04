import SwiftUI

// MARK: - Colours
// The same palette as the web app: paper background, indigo for actions, green
// for passed, and masculine/feminine tints on nouns.

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that follows light and dark mode.
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

enum Palette {
    static let paper = Color.adaptive(0xF4F6FB, 0x0D1017)
    static let card = Color.adaptive(0xFFFFFF, 0x171B25)
    static let ink = Color.adaptive(0x141A2A, 0xEDF1FA)
    static let muted = Color.adaptive(0x5B6480, 0x9AA3BC)
    static let faint = Color.adaptive(0xC3CADB, 0x3A4356)
    static let rule = Color.adaptive(0xE4E8F2, 0x262C3A)
    static let pen = Color.adaptive(0x2F3BD4, 0x7D88FF)
    static let penSoft = Color.adaptive(0xE7E9FD, 0x222A4D)
    static let good = Color.adaptive(0x12794A, 0x4ADE9B)
    static let goodSoft = Color.adaptive(0xDFF5E9, 0x14301F)
    static let bad = Color.adaptive(0xB3261E, 0xFF8A80)
    static let badSoft = Color.adaptive(0xFCE8E6, 0x3A1D1B)
    static let warnSoft = Color.adaptive(0xFFF4DB, 0x3A2F15)
    static let warn = Color.adaptive(0x8A5A00, 0xFFC95C)
    static let masc = Color.adaptive(0x1A62B3, 0x7FB6F2)
    static let mascSoft = Color.adaptive(0xDEEDFB, 0x18304A)
    static let fem = Color.adaptive(0xA8347C, 0xF29BD0)
    static let femSoft = Color.adaptive(0xFBE3F2, 0x40203A)

    static func genderColour(_ gender: String) -> Color {
        switch gender {
        case "m": return masc
        case "f": return fem
        default: return ink
        }
    }

    static func genderTint(_ gender: String) -> Color {
        switch gender {
        case "m": return mascSoft
        case "f": return femSoft
        default: return penSoft
        }
    }
}

// MARK: - Fonts

extension Font {
    /// French words are set in a serif, so they stand apart from the English.
    static func french(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Building blocks

struct CardBox<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.rule, lineWidth: 1)
        )
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Palette.penSoft
    var ink: Color = Palette.pen

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint)
            .foregroundStyle(ink)
            .clipShape(Capsule())
    }
}

struct ProgressBar: View {
    var value: Double          // 0...1
    var height: CGFloat = 10
    var tint: Color = Palette.pen

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.rule)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.pen
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(filled ? tint : Palette.card)
            .foregroundStyle(filled ? Color.white : Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(filled ? Color.clear : Palette.rule, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SmallButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(filled ? Palette.pen : Palette.card)
            .foregroundStyle(filled ? Color.white : Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(filled ? Color.clear : Palette.rule, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A round speaker button.
struct SpeakButton: View {
    let text: String
    var size: CGFloat = 44
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: Speech

    var body: some View {
        Button {
            speech.speak(text, settings: store.state.settings)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: size * 0.38))
                .foregroundStyle(Palette.pen)
                .frame(width: size, height: size)
                .background(Palette.card)
                .clipShape(Circle())
                .overlay(Circle().stroke(Palette.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hear it spoken")
    }
}

/// Small banner used for notices, same as the web app's coloured strips.
struct Notice: View {
    let text: String
    var tone: Tone = .warn

    enum Tone { case warn, good }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tone == .good ? Palette.goodSoft : Palette.warnSoft)
            .foregroundStyle(tone == .good ? Palette.good : Palette.warn)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Brief message at the bottom of the screen, like the web app's toast.
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.ink)
            .foregroundStyle(Palette.paper)
            .clipShape(Capsule())
            .shadow(radius: 8, y: 3)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    func screenBackground() -> some View {
        self.background(Palette.paper.ignoresSafeArea())
    }
}
