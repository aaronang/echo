import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SERVERS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: appVM.addServer) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
        }
    }
}
