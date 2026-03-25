import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        List(appVM.servers, selection: $appVM.selectedServerID) { server in
            ServerRowView(
                config: server,
                isRunning: appVM.processManager(for: server.id).isRunning
            )
            .tag(server.id)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    appVM.deleteServer(server.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Servers")
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Spacer()
                Button(action: appVM.addServer) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
