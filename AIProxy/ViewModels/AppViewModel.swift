import Foundation
import SwiftUI

@MainActor
class AppViewModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var selectedServerID: UUID?
    @Published var serverProcesses: [UUID: ProcessManager] = [:]
    @AppStorage("aiProxyPath") var aiProxyPath: String = ""

    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    init() {
        loadServers()
        if servers.isEmpty {
            let defaultServer = ServerConfig(name: "Claude Proxy", port: 3000, provider: .claude)
            servers.append(defaultServer)
            selectedServerID = defaultServer.id
            saveServers()
        } else {
            selectedServerID = servers.first?.id
        }
    }

    func addServer() {
        let nextPort = (servers.map(\.port).max() ?? 2999) + 1
        let server = ServerConfig(name: "New Server", port: nextPort, provider: .claude)
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
        let path = aiProxyPath.isEmpty ? detectAIProxyPath() : aiProxyPath
        processManager(for: id).start(aiProxyPath: path, provider: config.provider, port: config.port)
    }

    func stopServer(_ id: UUID) {
        processManager(for: id).stop()
    }

    private func detectAIProxyPath() -> String {
        let candidates = [
            NSHomeDirectory() + "/Code/ai-proxy",
            NSHomeDirectory() + "/code/ai-proxy",
            NSHomeDirectory() + "/Projects/ai-proxy",
            NSHomeDirectory() + "/Developer/ai-proxy",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path + "/index.mjs") {
                aiProxyPath = path
                return path
            }
        }
        return NSHomeDirectory() + "/Code/ai-proxy"
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
