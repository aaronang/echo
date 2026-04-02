import Foundation
import SwiftUI

@MainActor
class AppViewModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var selectedServerID: UUID?
    @Published var serverProcesses: [UUID: ProcessManager] = [:]

    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    init() {
        loadServers()
        if servers.isEmpty {
            let defaultServer = ServerConfig(name: "New Server", port: 3000, provider: .auggie)
            servers.append(defaultServer)
            selectedServerID = defaultServer.id
            saveServers()
        } else {
            selectedServerID = servers.first?.id
        }
    }

    func addServer() {
        let nextPort = (servers.map(\.port).max() ?? 2999) + 1
        let server = ServerConfig(name: "New Server", port: nextPort, provider: .auggie)
        servers.append(server)
        selectedServerID = server.id
        saveServers()
    }

    func deleteServer(_ id: UUID) {
        processManager(for: id).stop()
        serverProcesses.removeValue(forKey: id)
        servers.removeAll { $0.id == id }
        if selectedServerID == id {
            selectedServerID = servers.first?.id
        }
        saveServers()
    }

    func updateServer(_ config: ServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
            saveServers()
        }
    }

    func processManager(for serverID: UUID) -> ProcessManager {
        if let pm = serverProcesses[serverID] { return pm }
        let pm = ProcessManager()
        serverProcesses[serverID] = pm
        return pm
    }

    func startServer(_ id: UUID) {
        guard let config = servers.first(where: { $0.id == id }) else { return }
        processManager(for: id).start(port: config.port, provider: config.provider, systemPrompt: config.systemPrompt)
    }

    func stopServer(_ id: UUID) {
        processManager(for: id).stop()
    }

    func stopAllServers() {
        for pm in serverProcesses.values {
            pm.stop()
        }
    }

    func restartServer(_ id: UUID) {
        guard let config = servers.first(where: { $0.id == id }) else { return }
        processManager(for: id).restart(port: config.port, provider: config.provider, systemPrompt: config.systemPrompt)
    }

    private func loadServers() {
        guard let data = try? Data(contentsOf: configURL),
              let configs = try? JSONDecoder().decode([ServerConfig].self, from: data) else { return }
        servers = configs
    }

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        try? data.write(to: configURL)
    }
}
