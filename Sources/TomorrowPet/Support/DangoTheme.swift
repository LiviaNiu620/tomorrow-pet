import SwiftUI

/// 三色团子设计系统：粉 / 白 / 抹茶绿 + 深墨描边与硬投影。
enum Dango {
    static let ink = Color(hex: 0x221F1C)
    static let ink2 = Color(hex: 0x34302C)
    static let ink3 = Color(hex: 0x4A4540)
    static let ground = Color(hex: 0xE8EDE3)
    static let paper = Color.white
    static let soft = Color(hex: 0xF2F5EE)
    static let softer = Color(hex: 0xF6F8F3)
    static let line = Color(hex: 0xCFD5C8)
    static let dash = Color(hex: 0xDCE2D5)
    static let muted = Color(hex: 0x5E625A)
    static let faint = Color(hex: 0x7A7E76)
    static let pink = Color(hex: 0xF48FB0)
    static let pinkLight = Color(hex: 0xF9C0D0)
    static let pinkDeep = Color(hex: 0xE35C86)
    static let pinkText = Color(hex: 0xB8335E)
    static let blush = Color(hex: 0xFFE3EC)
    static let blushSoft = Color(hex: 0xFFF6F9)
    static let green = Color(hex: 0xB9DD9C)
    static let greenLight = Color(hex: 0xBFDDA8)
    static let greenDeep = Color(hex: 0x7DB35B)
    static let greenText = Color(hex: 0x3F6B2C)
    static let butter = Color(hex: 0xFBD38D)
    static let apricot = Color(hex: 0xFBDDB8)
    static let lavender = Color(hex: 0xE0D4F7)
    static let sky = Color(hex: 0xC9DDF7)
    static let skewer = Color(hex: 0xC9A27A)
    static let sidebarText = Color(hex: 0xEDEAE4)
    static let sidebarMuted = Color(hex: 0xB9B3AA)

    /// 领域浅色填充（文字始终用墨色，保证对比度）。
    static func areaFill(_ colorName: String?) -> Color {
        switch colorName {
        case "blue": Color(hex: 0xC9DDF7)
        case "purple": Color(hex: 0xE0D4F7)
        case "pink": Color(hex: 0xF9D0DC)
        case "orange": Color(hex: 0xFBDDB8)
        case "green": Color(hex: 0xE2EFBE)
        case "teal": Color(hex: 0xC6EBDD)
        default: Color(hex: 0xECEFE8)
        }
    }

    static func priorityFill(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: pink
        case .medium: butter
        case .low: Color(hex: 0xE2EFBE)
        case .none: paper
        }
    }

    static func capacityFill(_ ratio: Double) -> Color {
        ratio > 0.85 ? pink : (ratio > 0.7 ? butter : green)
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Card

struct DangoCardModifier: ViewModifier {
    var fill: Color = Dango.paper
    var shadow: Color = Dango.ink
    var radius: CGFloat = 18
    var lineWidth: CGFloat = 2
    var offset: CGFloat = 4
    var padding: CGFloat? = 18

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(shadow)
                        .offset(x: offset, y: offset)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Dango.ink, lineWidth: lineWidth)
                }
            }
    }
}

extension View {
    func dangoCard(
        fill: Color = Dango.paper,
        shadow: Color = Dango.ink,
        radius: CGFloat = 18,
        offset: CGFloat = 4,
        padding: CGFloat? = 18
    ) -> some View {
        modifier(DangoCardModifier(fill: fill, shadow: shadow, radius: radius, offset: offset, padding: padding))
    }

    /// 小号硬投影描边块（任务块、胶囊等）。
    func dangoBlock(fill: Color, radius: CGFloat = 10, shadow: CGFloat = 2, highlighted: Bool = false, dashed: Bool = false) -> some View {
        background {
            ZStack {
                if shadow > 0 && !dashed {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Dango.ink)
                        .offset(x: shadow, y: shadow)
                }
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                if dashed {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Dango.ink, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Dango.ink, lineWidth: 2)
                }
                if highlighted {
                    RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                        .strokeBorder(Dango.pinkDeep, lineWidth: 3)
                        .padding(-4)
                }
            }
        }
    }
}

// MARK: - Buttons

enum DangoButtonKind { case plain, pink, green, ink, ghost }

struct DangoButtonStyle: ButtonStyle {
    var kind: DangoButtonKind = .plain
    var small = false
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadow: CGFloat = kind == .ghost ? 0 : (small ? 1.5 : 2)
        configuration.label
            .font(Dango.font(small ? 12 : 13, .bold))
            .lineLimit(1)
            .fixedSize(horizontal: !fullWidth, vertical: false)
            .padding(.horizontal, small ? 10 : 15)
            .padding(.vertical, small ? 4 : 8)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    if shadow > 0 {
                        Capsule().fill(Dango.ink).offset(x: pressed ? 0 : shadow, y: pressed ? 0 : shadow)
                    }
                    Capsule().fill(background)
                    Capsule().strokeBorder(kind == .ghost ? Dango.sidebarText : Dango.ink, lineWidth: 2)
                }
            }
            .offset(x: pressed ? shadow / 2 : 0, y: pressed ? shadow / 2 : 0)
            .contentShape(Capsule())
    }

    private var background: Color {
        switch kind {
        case .plain: Dango.paper
        case .pink: Dango.pink
        case .green: Dango.green
        case .ink: Dango.ink
        case .ghost: .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .ink, .ghost: .white
        default: Dango.ink
        }
    }
}

extension ButtonStyle where Self == DangoButtonStyle {
    static func dango(_ kind: DangoButtonKind = .plain, small: Bool = false, fullWidth: Bool = false) -> DangoButtonStyle {
        DangoButtonStyle(kind: kind, small: small, fullWidth: fullWidth)
    }
}

/// 无样式、带命中区域的按钮。
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Small components

struct DangoChip: View {
    let text: String
    var fill: Color = Dango.paper
    var mono = false

    var body: some View {
        Text(text)
            .font(mono ? Dango.mono(11.5) : Dango.font(11.5, .bold))
            .foregroundStyle(Dango.ink)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 1.5))
    }
}

struct DangoTag: View {
    let text: String
    var fill: Color = Dango.pink

    var body: some View {
        Text(text)
            .font(Dango.font(10, .heavy))
            .foregroundStyle(Dango.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Dango.ink, lineWidth: 1.5))
    }
}

struct DangoSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(Dango.font(13, .heavy))
                        .foregroundStyle(selected ? Color.white : Dango.ink)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Dango.ink : Color.clear))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Dango.paper))
        .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
        .fixedSize()
    }
}

struct DangoCheck: View {
    let done: Bool
    var size: CGFloat = 20
    var fill: Color = Dango.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(done ? fill : Dango.paper)
                Circle().strokeBorder(Dango.ink, lineWidth: 2)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .heavy))
                        .foregroundStyle(fill == Dango.ink ? Color.white : Dango.ink)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(done ? "标记为未完成" : "完成")
    }
}

struct DangoProgressBar: View {
    let value: Double
    var fill: Color = Dango.green
    var height: CGFloat = 12
    var track: Color = Dango.paper

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Rectangle()
                    .fill(fill)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
                    .overlay(alignment: .trailing) {
                        if value > 0.02 && value < 0.98 { Rectangle().fill(Dango.ink).frame(width: 1.5) }
                    }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: height > 9 ? 2 : 1.5))
        }
        .frame(height: height)
    }
}

struct DangoRing: View {
    let progress: Double
    var color: Color = Dango.greenDeep
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Dango.ground, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct DangoSquareDot: View {
    let fill: Color
    var size: CGFloat = 12
    var border: Color = Dango.ink

    var body: some View {
        RoundedRectangle(cornerRadius: size / 3)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: size / 3).strokeBorder(border, lineWidth: 1.5))
            .frame(width: size, height: size)
    }
}

struct DangoField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Dango.font(13))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Dango.paper))
            .overlay(Capsule().strokeBorder(Dango.ink, lineWidth: 2))
            .onSubmit(onSubmit)
    }
}

struct DangoTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 60

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(Dango.font(13))
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder)
                    .font(Dango.font(13))
                    .foregroundStyle(Dango.faint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight, maxHeight: minHeight * 1.8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Dango.softer))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Dango.ink, lineWidth: 2))
    }
}

struct DashedDivider: View {
    var color: Color = Dango.dash
    var body: some View {
        Rectangle()
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(height: 1)
    }
}

struct DangoPageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(Dango.font(13, .bold))
                    .foregroundStyle(Dango.muted)
                Text(title)
                    .font(Dango.font(34, .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Dango.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension DangoPageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

// MARK: - Mascot

enum DangoMood { case happy, calm, sleepy, focused }

/// 原创三色团子吉祥物；eaten 表示已被“吃掉”的团子个数（从上往下）。
struct DangoMascot: View {
    var mood: DangoMood = .happy
    var eaten: Int = 0
    var outline: Color = Dango.ink
    var size: CGFloat = 60

    var body: some View {
        let r = size * 0.28
        let gap = r * 1.8
        ZStack {
            Capsule()
                .fill(Dango.skewer)
                .frame(width: size * 0.07, height: gap * 2 + r * 2.6)
            ball(Dango.pinkLight).frame(width: r * 2, height: r * 2)
                .offset(y: -gap)
                .opacity(eaten >= 1 ? 0.12 : 1)
            ball(.white).frame(width: r * 2, height: r * 2)
                .opacity(eaten >= 2 ? 0.12 : 1)
                .overlay(face(r: r).opacity(eaten >= 2 ? 0 : 1))
            ball(Dango.greenLight).frame(width: r * 2, height: r * 2)
                .offset(y: gap)
                .overlay(face(r: r).offset(y: gap).opacity(eaten >= 2 ? 1 : 0))
        }
        .frame(width: size, height: gap * 2 + r * 2.8)
        .accessibilityHidden(true)
    }

    private func ball(_ fill: Color) -> some View {
        Circle().fill(fill).overlay(Circle().strokeBorder(outline, lineWidth: max(1.5, size * 0.045)))
    }

    private func face(r: CGFloat) -> some View {
        ZStack {
            HStack(spacing: r * 0.62) {
                eye(r: r)
                eye(r: r)
            }
            .offset(y: -r * 0.12)
            mouth(r: r).offset(y: r * 0.32)
            HStack(spacing: r * 1.05) {
                Ellipse().fill(Dango.pink).frame(width: r * 0.42, height: r * 0.24)
                Ellipse().fill(Dango.pink).frame(width: r * 0.42, height: r * 0.24)
            }
            .offset(y: r * 0.32)
        }
    }

    @ViewBuilder
    private func eye(r: CGFloat) -> some View {
        if mood == .sleepy {
            Capsule().fill(Dango.ink).frame(width: r * 0.28, height: r * 0.07)
        } else {
            Circle().fill(Dango.ink).frame(width: r * 0.17, height: r * 0.17)
        }
    }

    @ViewBuilder
    private func mouth(r: CGFloat) -> some View {
        switch mood {
        case .focused, .sleepy:
            Capsule().fill(Dango.ink).frame(width: r * 0.36, height: max(1.4, r * 0.07))
        default:
            SmileShape()
                .stroke(Dango.ink, style: StrokeStyle(lineWidth: max(1.4, r * 0.08), lineCap: .round))
                .frame(width: r * 0.4, height: r * 0.16)
        }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.8))
        return path
    }
}

extension TaskStore {
    func area(for task: TaskItem) -> TaskArea? {
        areas.first { $0.id == task.areaID }
    }

    func fill(for task: TaskItem) -> Color {
        Dango.areaFill(area(for: task)?.colorName)
    }
}
