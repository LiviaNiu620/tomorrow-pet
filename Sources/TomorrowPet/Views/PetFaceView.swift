import SwiftUI

enum PetMood {
    case idle
    case planning
    case happy
    case sleeping
}

struct PetFaceView: View {
    var mood: PetMood = .idle

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ear(x: -0.27 * size, rotation: -18)
                ear(x: 0.27 * size, rotation: 18)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.82), Color.teal],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: max(1, size * 0.025)))
                    .padding(size * 0.09)

                face(size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityMood)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func ear(x: CGFloat, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.teal.opacity(0.9))
            .frame(width: 24, height: 34)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: -27)
    }

    @ViewBuilder
    private func face(size: CGFloat) -> some View {
        switch mood {
        case .sleeping:
            HStack(spacing: size * 0.2) {
                Capsule().frame(width: size * 0.14, height: size * 0.025)
                Capsule().frame(width: size * 0.14, height: size * 0.025)
            }
            .foregroundStyle(.white.opacity(0.9))
            .offset(y: -size * 0.04)
        default:
            HStack(spacing: size * 0.22) {
                Circle().frame(width: size * 0.075)
                Circle().frame(width: size * 0.075)
            }
            .foregroundStyle(.white)
            .offset(y: -size * 0.08)
        }

        if mood == .happy {
            Image(systemName: "chevron.down")
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: size * 0.13)
        } else {
            Capsule()
                .fill(.white.opacity(0.92))
                .frame(width: size * 0.13, height: size * 0.035)
                .offset(y: size * 0.12)
        }

        Circle()
            .fill(.pink.opacity(0.45))
            .frame(width: size * 0.11)
            .offset(x: -size * 0.25, y: size * 0.08)
        Circle()
            .fill(.pink.opacity(0.45))
            .frame(width: size * 0.11)
            .offset(x: size * 0.25, y: size * 0.08)
    }

    private var accessibilityMood: String {
        switch mood {
        case .idle: "空闲的桌面宠物团子"
        case .planning: "正在准备规划的团子"
        case .happy: "开心的团子"
        case .sleeping: "正在休息的团子"
        }
    }
}
