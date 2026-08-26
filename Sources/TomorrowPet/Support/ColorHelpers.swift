import SwiftUI

extension Color {
    static func areaColor(named name: String) -> Color {
        switch name {
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "orange": .orange
        case "green": .green
        default: .teal
        }
    }
}

extension Date {
    var shortDayText: String {
        formatted(.dateTime.month(.abbreviated).day())
    }
}
