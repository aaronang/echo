import Foundation

enum SSEFrame {
    case sessionID(String)
    case thinking(String)
    case text(String)
    case error(String)
    case done
}

final class ProviderProcess {
    private var process: Process?

    func start(
        provider: Provider,
        prompt: String,
        sessionID: String?,
        systemPrompt: String,
        onFrame: @escaping @Sendable (SSEFrame) -> Void,
        onLog: (@Sendable (String) -> Void)? = nil,
        onComplete: @escaping @Sendable (Int) -> Void
    ) {
        switch provider {
        case .claude:
            startClaude(prompt: prompt, sessionID: sessionID, systemPrompt: systemPrompt,
                        onFrame: onFrame, onLog: onLog, onComplete: onComplete)
        case .auggie:
            startBatch(command: "auggie",
                       args: buildAuggieArgs(prompt: prompt, sessionID: sessionID),
                       systemPrompt: systemPrompt, onFrame: onFrame, onLog: onLog, onComplete: onComplete)
        case .droid:
            startBatch(command: "droid",
                       args: buildDroidArgs(prompt: prompt, sessionID: sessionID),
                       systemPrompt: systemPrompt, onFrame: onFrame, onLog: onLog, onComplete: onComplete)
        }
    }

    func kill() {
        process?.terminate()
    }

    // MARK: - Claude (streaming JSON lines)

    private func startClaude(
        prompt: String,
        sessionID: String?,
        systemPrompt: String,
        onFrame: @escaping @Sendable (SSEFrame) -> Void,
        onLog: (@Sendable (String) -> Void)?,
        onComplete: @escaping @Sendable (Int) -> Void
    ) {
        var args = ["-p", "--output-format", "stream-json", "--verbose",
                    "--include-partial-messages", "--effort", "high", "--tools", ""]
        if let sid = sessionID { args += ["--resume", sid] }

        let p = makeProcess(command: "claude", args: args, systemPrompt: systemPrompt)
        process = p

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        var buffer = ""
        var finished = false

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer += chunk
            let lines = buffer.components(separatedBy: "\n")
            buffer = lines.last ?? ""
            for line in lines.dropLast() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let eventData = trimmed.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any]
                else { continue }

                guard let type = event["type"] as? String else { continue }

                if type == "system",
                   let subtype = event["subtype"] as? String, subtype == "init",
                   let sid = event["session_id"] as? String {
                    onFrame(.sessionID(sid))
                } else if type == "stream_event",
                          let inner = event["event"] as? [String: Any],
                          inner["type"] as? String == "content_block_delta",
                          let delta = inner["delta"] as? [String: Any] {
                    if delta["type"] as? String == "thinking_delta",
                       let thinking = delta["thinking"] as? String {
                        onFrame(.thinking(thinking))
                    } else if delta["type"] as? String == "text_delta",
                              let text = delta["text"] as? String {
                        onFrame(.text(text))
                    }
                } else if type == "result" {
                    if let isError = event["is_error"] as? Bool, isError,
                       let result = event["result"] as? String {
                        onLog?("Error: \(result)")
                    }
                    finished = true
                    onFrame(.done)
                    onComplete(200)
                }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { _ in }

        p.terminationHandler = { proc in
            guard !finished else { return }
            if proc.terminationStatus != 0 {
                onLog?("Error: claude exited with code \(proc.terminationStatus)")
                onFrame(.error("claude exited with code \(proc.terminationStatus)"))
                onComplete(500)
            }
        }

        do {
            try p.run()
            stdin.fileHandleForWriting.write(prompt.data(using: .utf8) ?? Data())
            stdin.fileHandleForWriting.closeFile()
        } catch {
            onLog?("Error: \(error.localizedDescription)")
            onFrame(.error(error.localizedDescription))
            onComplete(500)
        }
    }

    // MARK: - Batch (auggie / droid — single JSON result)

    private func startBatch(
        command: String,
        args: [String],
        systemPrompt: String,
        onFrame: @escaping @Sendable (SSEFrame) -> Void,
        onLog: (@Sendable (String) -> Void)?,
        onComplete: @escaping @Sendable (Int) -> Void
    ) {
        let p = makeProcess(command: command, args: args, systemPrompt: systemPrompt)
        process = p

        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr

        var output = ""
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            output += chunk
        }
        stderr.fileHandleForReading.readabilityHandler = { _ in }

        p.terminationHandler = { _ in
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                onFrame(.error("Failed to parse \(command) output"))
                onFrame(.done)
                onComplete(500)
                return
            }
            if let sid = event["session_id"] as? String {
                onFrame(.sessionID(sid))
            }
            if let isError = event["is_error"] as? Bool, isError,
               let result = event["result"] as? String {
                onLog?("Error: \(result)")
                onFrame(.error(result))
                onFrame(.done)
                onComplete(500)
            } else if let result = event["result"] as? String {
                onFrame(.text(result))
                onFrame(.done)
                onComplete(200)
            } else {
                onLog?("Error: empty response from \(command)")
                onFrame(.error("Empty response from \(command)"))
                onFrame(.done)
                onComplete(500)
            }
        }

        do {
            try p.run()
        } catch {
            onLog?("Error: \(error.localizedDescription)")
            onFrame(.error(error.localizedDescription))
            onComplete(500)
        }
    }

    // MARK: - Helpers

    private static let baseSystemPrompt = """
    You are a helpful AI assistant. The user may ask you anything — do not assume this is a coding or software engineering task unless they explicitly say so. Respond naturally and helpfully to whatever the user asks. You do not have access to a file system and should not attempt to read, write, or reference local files. You are able to search the web to find up-to-date information when needed.
    """

    private func makeProcess(command: String, args: [String], systemPrompt: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: resolveCommand(command))
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.resolvedPATH
        let combined = systemPrompt.isEmpty
            ? Self.baseSystemPrompt
            : Self.baseSystemPrompt + "\n\n" + systemPrompt
        env["SYSTEM_PROMPT"] = combined
        p.environment = env
        return p
    }

    static func isAvailable(_ provider: Provider) -> Bool {
        let command = provider.rawValue
        return candidatePaths(for: command).contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func resolveCommand(_ command: String) -> String {
        Self.candidatePaths(for: command).first { FileManager.default.fileExists(atPath: $0) }
            ?? "/opt/homebrew/bin/\(command)"
    }

    private static func candidatePaths(for command: String) -> [String] {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        var paths = [
            "\(home)/.local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
        ]
        for binDir in nvmBinDirs {
            paths.insert("\(binDir)/\(command)", at: 0)
        }
        return paths
    }

    private static var resolvedPATH: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        var parts = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for binDir in nvmBinDirs.reversed() {
            parts.insert(binDir, at: 0)
        }
        return parts.joined(separator: ":")
    }

    private static var nvmBinDirs: [String] {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let nvmNodeDir = "\(home)/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvmNodeDir)) ?? []
        return versions.sorted().reversed().map { "\(nvmNodeDir)/\($0)/bin" }
    }

    private func buildAuggieArgs(prompt: String, sessionID: String?) -> [String] {
        var args = ["-p", "--output-format", "json", "--instruction", prompt]
        if let sid = sessionID { args += ["--resume", sid] }
        return args
    }

    private func buildDroidArgs(prompt: String, sessionID: String?) -> [String] {
        var args = ["exec", "--output-format", "json"]
        if let sid = sessionID { args += ["--session-id", sid] }
        args.append(prompt)
        return args
    }
}
