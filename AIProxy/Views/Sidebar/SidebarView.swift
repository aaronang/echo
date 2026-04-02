import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var renamingID: UUID? = nil

    var body: some View {
        List(appVM.servers, selection: $appVM.selectedServerID) { server in
            ServerRowView(
                config: server,
                processManager: appVM.processManager(for: server.id),
                isRenaming: renamingID == server.id,
                onCommit: { newName in
                    var updated = server
                    updated.name = newName
                    appVM.updateServer(updated)
                    renamingID = nil
                },
                onCancel: {
                    renamingID = nil
                }
            )
            .tag(server.id)
            .contextMenu {
                Button("Rename") {
                    renamingID = server.id
                }
                Button("Copy API URL") {
                    let url = "http://localhost:\(server.port)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
                Divider()
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
        .onKeyPress(.return) {
            guard renamingID == nil, appVM.selectedServerID != nil else { return .ignored }
            renamingID = appVM.selectedServerID
            return .handled
        }
    }
}
