import SwiftUI

struct ServerRowView: View {
    let config: ServerConfig
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRunning {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(":\(config.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(config.provider.badge)
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.15))
                .foregroundStyle(badgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 2)
    }

    private var badgeColor: Color {
        switch config.provider.badgeColor {
        case "orange": return .orange
        case "blue": return .blue
        case "green": return .green
        default: return .secondary
        }
    }
}
