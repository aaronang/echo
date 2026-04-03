import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = appVM.saveError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") { appVM.saveError = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
            }
            NavigationSplitView {
            SidebarView()
                .environmentObject(appVM)
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
        } detail: {
            if let selectedID = appVM.selectedServerID {
                ServerDetailView(serverID: selectedID)
                    .environmentObject(appVM)
                    .id(selectedID)
            } else {
                Text("Select a server")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        }
    }
}
