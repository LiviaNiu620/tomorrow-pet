import SwiftUI

enum AppTheme {
    static let accent = adaptive(light: (0.73, 0.16, 0.18), dark: (1.0, 0.48, 0.46))
    static let accentSoft = Color(red: 0.96, green: 0.74, blue: 0.70)
    static let sky = adaptive(light: (0.22, 0.43, 0.56), dark: (0.52, 0.74, 0.87))
    static let butter = Color(red: 0.96, green: 0.84, blue: 0.48)
    // The pet is a light illustration in both appearances; its outlines stay dark.
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let success = adaptive(light: (0.16, 0.43, 0.35), dark: (0.43, 0.78, 0.64))
    static let warning = adaptive(light: (0.57, 0.35, 0.08), dark: (1.0, 0.71, 0.36))
    static let cardRadius: CGFloat = 16
    static let pageInset: CGFloat = 28

    private static func adaptive(
        light: (Double, Double, Double), dark: (Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }

    static func priority(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: accent
        case .medium: warning
        case .low: sky
        case .none: .secondary
        }
    }
}

struct PetGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label
                .font(.headline)
                .foregroundStyle(.primary)
            configuration.content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 0.75)
        }
    }
}

struct PetDetailBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.sky.opacity(0.04), Color.clear, AppTheme.accentSoft.opacity(0.025)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PetStatusPill: View {
    let text: String
    let systemImage: String
    var color: Color = AppTheme.sky

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.09), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct PetPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var systemImage: String = "sparkles"

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(eyebrow, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.sky)
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            PetFaceView(mood: .planning)
                .frame(width: 64, height: 64)
                .padding(10)
                .background(AppTheme.accentSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PetMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var color: Color = AppTheme.sky

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title3.weight(.semibold).monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// Switch columns using available detail width, including when the sidebar is resized.
struct PetAdaptiveColumns<Primary: View, Secondary: View>: View {
    let availableWidth: CGFloat
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        if availableWidth >= 820 {
            HStack(alignment: .top, spacing: 20) {
                primary().frame(maxWidth: .infinity, alignment: .topLeading)
                secondary().frame(width: min(340, availableWidth * 0.35), alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                primary()
                secondary()
            }
        }
    }
}

struct PetEmptyState: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.sky)
                .frame(width: 76, height: 76)
                .background(AppTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            VStack(spacing: 7) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}
