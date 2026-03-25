import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(appVM)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
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
        .navigationTitle("AI Proxy")
    }
}
