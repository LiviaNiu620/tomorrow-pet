import SwiftUI

enum PetMood {
    case idle
    case planning
    case happy
    case sleeping
}

/// 纯 SwiftUI 绘制的史努比桌面宠物，不依赖外部位图资源。
struct PetFaceView: View {
    var mood: PetMood = .idle

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.96), AppTheme.sky.opacity(0.11)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(size * 0.035)
                    .shadow(color: .black.opacity(0.12), radius: size * 0.07, y: size * 0.035)

                collar(size: size)
                blackEar(size: size)

                SnoopyHeadShape()
                    .fill(Color.white)
                    .overlay {
                        SnoopyHeadShape()
                            .stroke(AppTheme.ink, lineWidth: max(1.5, size * 0.022))
                    }
                    .frame(width: size * 0.69, height: size * 0.66)
                    .offset(x: -size * 0.015, y: -size * 0.035)

                faceDetails(size: size)

                if mood == .planning {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.15, weight: .semibold))
                        .foregroundStyle(AppTheme.butter)
                        .offset(x: size * 0.31, y: -size * 0.30)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityMood)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func collar(size: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(AppTheme.accent)
                .frame(width: size * 0.45, height: size * 0.10)
                .rotationEffect(.degrees(-4))
            Circle()
                .fill(AppTheme.butter)
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: max(1, size * 0.012)))
                .frame(width: size * 0.105, height: size * 0.105)
                .offset(y: size * 0.055)
        }
        .offset(x: size * 0.045, y: size * 0.285)
    }

    private func blackEar(size: CGFloat) -> some View {
        Capsule()
            .fill(AppTheme.ink)
            .frame(width: size * 0.28, height: size * 0.52)
            .rotationEffect(.degrees(-15))
            .offset(x: size * 0.225, y: size * 0.005)
    }

    @ViewBuilder
    private func faceDetails(size: CGFloat) -> some View {
        Ellipse()
            .fill(AppTheme.ink)
            .frame(width: size * 0.145, height: size * 0.105)
            .rotationEffect(.degrees(-10))
            .offset(x: -size * 0.285, y: size * 0.015)

        eye(size: size)

        SnoopySmileShape(isHappy: mood == .happy)
            .stroke(AppTheme.ink, style: StrokeStyle(lineWidth: max(1.2, size * 0.018), lineCap: .round))
            .frame(width: size * 0.20, height: size * 0.13)
            .offset(x: -size * 0.115, y: size * 0.115)

        if mood == .happy {
            Circle()
                .fill(AppTheme.accentSoft.opacity(0.55))
                .frame(width: size * 0.09, height: size * 0.065)
                .offset(x: size * 0.075, y: size * 0.10)
        }
    }

    @ViewBuilder
    private func eye(size: CGFloat) -> some View {
        switch mood {
        case .sleeping, .happy:
            SnoopyClosedEyeShape()
                .stroke(AppTheme.ink, style: StrokeStyle(lineWidth: max(1.3, size * 0.020), lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.07)
                .offset(x: size * 0.005, y: -size * 0.09)
        case .idle, .planning:
            Capsule()
                .fill(AppTheme.ink)
                .frame(width: size * 0.030, height: size * 0.088)
                .offset(x: size * 0.005, y: -size * 0.085)
        }
    }

    private var accessibilityMood: String {
        switch mood {
        case .idle: "空闲的桌面史努比"
        case .planning: "正在规划的桌面史努比"
        case .happy: "开心的桌面史努比"
        case .sleeping: "正在休息的桌面史努比"
        }
    }
}

private struct SnoopyHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.20))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.48),
            control1: CGPoint(x: rect.width * 0.16, y: rect.height * 0.17),
            control2: CGPoint(x: rect.width * 0.05, y: rect.height * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.75),
            control1: CGPoint(x: rect.width * 0.08, y: rect.height * 0.67),
            control2: CGPoint(x: rect.width * 0.17, y: rect.height * 0.77)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.73, y: rect.height * 0.82),
            control1: CGPoint(x: rect.width * 0.43, y: rect.height * 0.91),
            control2: CGPoint(x: rect.width * 0.63, y: rect.height * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.93, y: rect.height * 0.47),
            control1: CGPoint(x: rect.width * 0.89, y: rect.height * 0.76),
            control2: CGPoint(x: rect.width * 0.98, y: rect.height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.69, y: rect.height * 0.16),
            control1: CGPoint(x: rect.width * 0.91, y: rect.height * 0.28),
            control2: CGPoint(x: rect.width * 0.82, y: rect.height * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.20),
            control1: CGPoint(x: rect.width * 0.56, y: rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.42, y: rect.height * 0.08)
        )
        path.closeSubpath()
        return path
    }
}

private struct SnoopyClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.60))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.55),
            control: CGPoint(x: rect.midX, y: rect.height * 0.20)
        )
        return path
    }
}

private struct SnoopySmileShape: Shape {
    let isHappy: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.22))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: isHappy ? rect.height * 0.15 : rect.height * 0.34),
            control: CGPoint(x: rect.midX, y: rect.height * (isHappy ? 0.95 : 0.68))
        )
        return path
    }
}
