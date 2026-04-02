import SwiftUI

struct StatusBarView: View {
    @ObservedObject var processManager: ProcessManager

    private let labelColor = Color(nsColor: NSColor(red: 0.447, green: 0.447, blue: 0.447, alpha: 1))
    private let valueColor = Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))

    var body: some View {
        HStack(spacing: 16) {
            stat("Requests", count: processManager.requestCount)
            stat("Errors", count: processManager.errorCount, isError: true)
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, count: Int, isError: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(labelColor)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isError && count > 0 ? .red : valueColor)
        }
    }
}
