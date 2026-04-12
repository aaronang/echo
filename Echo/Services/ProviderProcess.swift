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
        model: String? = nil,
        systemPrompt: String,
        onFrame: @escaping @Sendable (SSEFrame) -> Void,
        onLog: (@Sendable (String) -> Void)? = nil,
        onComplete: @escaping @Sendable (Int) -> Void
    ) {
        switch provider {
        case .claude:
            startClaude(prompt: prompt, sessionID: sessionID, model: model,
                        systemPrompt: systemPrompt, onFrame: onFrame, onLog: onLog, onComplete: onComplete)
        case .auggie:
            startBatch(command: "auggie",
                       args: buildAuggieArgs(prompt: prompt, sessionID: sessionID, model: model),
                       systemPrompt: systemPrompt, onFrame: onFrame, onLog: onLog, onComplete: onComplete)
        case .droid:
            startBatch(command: "droid",
                       args: buildDroidArgs(prompt: prompt, sessionID: sessionID, model: model),
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
        model: String?,
        systemPrompt: String,
        onFrame: @escaping @Sendable (SSEFrame) -> Void,
        onLog: (@Sendable (String) -> Void)?,
        onComplete: @escaping @Sendable (Int) -> Void
    ) {
        var args = ["-p", "--output-format", "stream-json", "--verbose",
                    "--include-partial-messages", "--effort", "high",
                    "--tools", "WebSearch,WebFetch",
                    "--allowedTools", "WebSearch,WebFetch"]
        if let m = model { args += ["--model", m] }
        if let sid = sessionID { args += ["--resume", sid] }

        let p = makeProcess(command: "claude", args: args, systemPrompt: systemPrompt)
        process = p

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        // @unchecked Sendable: all mutations are protected by lock.
        final class ClaudeState: @unchecked Sendable {
            let lock = NSLock()
            var buffer = ""
            var finished = false
        }
        let state = ClaudeState()

        // Ensures onComplete is called at most once from any thread.
        let completeOnce: @Sendable (Int) -> Void = { status in
            state.lock.lock()
            let first = !state.finished
            state.finished = true
            state.lock.unlock()
            if first { onComplete(status) }
        }

        // Parses accumulated lines and fires frames. Must be called while NOT holding lock
        // (frames are delivered immediately; lock is re-acquired inside completeOnce).
        let processLines: () -> Void = {
            let lines = state.buffer.components(separatedBy: "\n")
            state.buffer = lines.last ?? ""
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
                    onFrame(.done)
                    completeOnce(200)
                    return
                }
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            state.lock.lock()
            state.buffer += chunk
            state.lock.unlock()
            processLines()
        }

        stderr.fileHandleForReading.readabilityHandler = { _ in }

        p.terminationHandler = { proc in
            // Disable handler and drain any data still buffered in the pipe.
            stdout.fileHandleForReading.readabilityHandler = nil
            let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
            if let chunk = String(data: remaining, encoding: .utf8), !chunk.isEmpty {
                state.lock.lock()
                state.buffer += chunk
                state.lock.unlock()
                processLines()
            }
            state.lock.lock()
            let alreadyFinished = state.finished
            state.lock.unlock()
            guard !alreadyFinished else { return }
            if proc.terminationStatus != 0 {
                onLog?("Error: claude exited with code \(proc.terminationStatus)")
                onFrame(.error("claude exited with code \(proc.terminationStatus)"))
            }
            completeOnce(500)
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

        stderr.fileHandleForReading.readabilityHandler = { _ in }

        p.terminationHandler = { _ in
            // Read all output after process exit — no readabilityHandler race possible.
            let raw = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmed: String
            if let braceIndex = raw.firstIndex(of: "{") {
                trimmed = String(raw[braceIndex...])
            } else {
                trimmed = raw
            }
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

    // MARK: - Model Listing

    struct ModelInfo {
        let id: String
        let displayName: String
    }

    static func listModels(for provider: Provider) -> [ModelInfo] {
        switch provider {
        case .claude: return claudeModels()
        case .auggie: return auggieModels()
        case .droid: return droidModels()
        }
    }

    private static func claudeModels() -> [ModelInfo] {
        [
            ModelInfo(id: "claude-opus-4-6", displayName: "Claude Opus 4.6"),
            ModelInfo(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
            ModelInfo(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5"),
            ModelInfo(id: "opus", displayName: "Claude Opus (alias)"),
            ModelInfo(id: "sonnet", displayName: "Claude Sonnet (alias)"),
            ModelInfo(id: "haiku", displayName: "Claude Haiku (alias)"),
        ]
    }

    private static func auggieModels() -> [ModelInfo] {
        [
            ModelInfo(id: "opus4.6", displayName: "Opus 4.6"),
            ModelInfo(id: "sonnet4.6", displayName: "Sonnet 4.6"),
            ModelInfo(id: "haiku4.5", displayName: "Haiku 4.5"),
            ModelInfo(id: "gpt5.2", displayName: "GPT-5.2"),
            ModelInfo(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro"),
        ]
    }

    private static func droidModels() -> [ModelInfo] {
        [
            ModelInfo(id: "claude-opus-4-6", displayName: "Claude Opus 4.6"),
            ModelInfo(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
            ModelInfo(id: "gpt-5.2", displayName: "GPT-5.2"),
            ModelInfo(id: "gpt-5.4", displayName: "GPT-5.4"),
            ModelInfo(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro"),
        ]
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

    private func buildAuggieArgs(prompt: String, sessionID: String?, model: String? = nil) -> [String] {
        var args = ["-p", "--output-format", "json", "--instruction", prompt]
        if let sid = sessionID { args += ["--resume", sid] }
        if let model = model { args += ["--model", model] }
        // Remove all non-web tools so only web-search and web-fetch remain.
        let removed = ["remove-files", "save-file", "apply_patch", "str-replace-editor", "view",
                       "launch-process", "kill-process", "read-process", "write-process", "list-processes",
                       "github-api", "sub-agent-explore", "sub-agent-plan",
                       "view_tasklist", "reorganize_tasklist", "update_tasks", "add_tasks",
                       "codebase-retrieval"]
        for tool in removed { args += ["--remove-tool", tool] }
        return args
    }

    private func buildDroidArgs(prompt: String, sessionID: String?, model: String? = nil) -> [String] {
        var args = ["exec", "--output-format", "json",
                    "--enabled-tools", "WebSearch,FetchUrl"]
        if let sid = sessionID { args += ["--session-id", sid] }
        if let model = model { args += ["--model", model] }
        args.append(prompt)
        return args
    }
}
