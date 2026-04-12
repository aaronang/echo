import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

final class ProxyServer {
    private let port: Int
    private let provider: Provider
    private let systemPrompt: String
    var onLog: (@Sendable (LogEntry) -> Void)?
    var onUnexpectedClose: (@Sendable () -> Void)?

    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    private var startGeneration: Int = 0

    init(port: Int, provider: Provider, systemPrompt: String) {
        self.port = port
        self.provider = provider
        self.systemPrompt = systemPrompt
    }

    func start() async throws {
        startGeneration += 1
        let generation = startGeneration

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let provider = self.provider
        let systemPrompt = self.systemPrompt
        let onLog = self.onLog

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        HTTPRequestHandler(provider: provider, systemPrompt: systemPrompt, onLog: onLog)
                    )
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()

        // If stop() was called while we were binding, shut down immediately.
        guard startGeneration == generation else {
            channel.close(promise: nil)
            try? await group.shutdownGracefully()
            return
        }
        self.group = group
        self.serverChannel = channel

        let onUnexpectedClose = self.onUnexpectedClose
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self, self.startGeneration == generation else { return }
            onUnexpectedClose?()
        }
    }

    func stop() async {
        startGeneration += 1  // Invalidate any in-flight start().
        let ch = serverChannel
        let grp = group
        serverChannel = nil
        group = nil
        try? await ch?.close().get()
        try? await grp?.shutdownGracefully()
    }
}

// MARK: - HTTP Channel Handler

private final class HTTPRequestHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let provider: Provider
    private let systemPrompt: String
    private let onLog: (@Sendable (LogEntry) -> Void)?

    private var requestHead: HTTPRequestHead?
    private var bodyBuffer = ByteBuffer()
    private var activeProcess: ProviderProcess?
    private var requestStart: Date?

    init(provider: Provider, systemPrompt: String, onLog: (@Sendable (LogEntry) -> Void)?) {
        self.provider = provider
        self.systemPrompt = systemPrompt
        self.onLog = onLog
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            bodyBuffer.clear()
            requestStart = Date()
        case .body(var buf):
            bodyBuffer.writeBuffer(&buf)
        case .end:
            handleRequest(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        activeProcess?.kill()
        activeProcess = nil
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        activeProcess?.kill()
        activeProcess = nil
        context.close(promise: nil)
    }

    // MARK: - Request Handling

    private func handleRequest(context: ChannelHandlerContext) {
        guard let head = requestHead else { return }

        if head.method == .OPTIONS {
            writeCORSPreflight(context: context)
            return
        }

        if head.method == .GET && head.uri == "/help" {
            writeHelp(context: context, version: head.version)
            return
        }

        if head.method == .GET && head.uri == "/v1/models" {
            handleListModels(context: context)
            return
        }

        guard head.method == .POST else {
            writeError(context: context, status: .notFound, message: "Not found")
            return
        }

        // Anthropic Messages API endpoint
        if head.uri == "/v1/messages" {
            handleAnthropicMessages(context: context)
            return
        }

        writeError(context: context, status: .notFound, message: "Not found")
    }

    // MARK: - Anthropic Messages API

    private func handleAnthropicMessages(context: ChannelHandlerContext) {
        guard let head = requestHead else { return }

        struct AnthropicMessage: Decodable {
            let role: String
            let content: String
        }
        struct AnthropicBody: Decodable {
            let model: String?
            let max_tokens: Int?
            let stream: Bool?
            let system: String?
            let messages: [AnthropicMessage]
        }

        let bytes = Data(bodyBuffer.readableBytesView)
        guard let body = try? JSONDecoder().decode(AnthropicBody.self, from: bytes) else {
            writeAnthropicError(context: context, status: .badRequest,
                                message: "Invalid request body")
            return
        }

        guard let lastUserMessage = body.messages.last(where: { $0.role == "user" }) else {
            writeAnthropicError(context: context, status: .badRequest,
                                message: "messages must contain at least one user message")
            return
        }

        let prompt = lastUserMessage.content
        let isStreaming = body.stream ?? false
        let msgID = "msg_\(UUID().uuidString.lowercased().prefix(24))"
        let modelName = body.model ?? "claude-sonnet-4-20250514"

        let startTime = requestStart ?? Date()
        let onLog = self.onLog
        let channel = context.channel

        onLog?(LogEntry(
            timestamp: startTime,
            method: "POST",
            path: "/v1/messages",
            info: "",
            statusCode: nil,
            latency: nil,
            isError: false,
            rawLine: "→ \(prompt)"
        ))

        let process = ProviderProcess()
        activeProcess?.kill()
        activeProcess = process

        if isStreaming {
            // SSE response headers
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/event-stream")
            headers.add(name: "Cache-Control", value: "no-cache")
            headers.add(name: "Connection", value: "keep-alive")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            let responseHead = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
            context.writeAndFlush(wrapOutboundOut(.head(responseHead)), promise: nil)

            // Send message_start
            let messageStartJSON = """
            {"type":"message_start","message":{"id":"\(msgID)","type":"message","role":"assistant","content":[],"model":"\(modelName)","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":0,"output_tokens":0}}}
            """
            Self.writeSSEEvent(channel: channel, event: "message_start", data: messageStartJSON)

            var hasThinking = false
            var thinkingBlockOpen = false
            var textBlockOpen = false
            var textBlockIndex = 0
            var responseText = ""
            var thinkingText = ""

            process.start(
                provider: provider,
                prompt: prompt,
                sessionID: nil,
                model: body.model,
                systemPrompt: systemPrompt,
                onFrame: { [weak channel] frame in
                    guard let channel else { return }
                    channel.eventLoop.execute {
                        switch frame {
                        case .thinking(let t):
                            thinkingText += t
                            if !hasThinking {
                                hasThinking = true
                                thinkingBlockOpen = true
                                textBlockIndex = 1
                                // Start thinking content block at index 0
                                Self.writeSSEEvent(channel: channel, event: "content_block_start",
                                    data: "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":\"\"}}")
                            }
                            let escaped = Self.jsonEscape(t)
                            Self.writeSSEEvent(channel: channel, event: "content_block_delta",
                                data: "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"\(escaped)\"}}")

                        case .text(let t):
                            responseText += t
                            // Close thinking block if open
                            if thinkingBlockOpen {
                                thinkingBlockOpen = false
                                Self.writeSSEEvent(channel: channel, event: "content_block_stop",
                                    data: "{\"type\":\"content_block_stop\",\"index\":0}")
                            }
                            // Open text block if needed
                            if !textBlockOpen {
                                textBlockOpen = true
                                Self.writeSSEEvent(channel: channel, event: "content_block_start",
                                    data: "{\"type\":\"content_block_start\",\"index\":\(textBlockIndex),\"content_block\":{\"type\":\"text\",\"text\":\"\"}}")
                            }
                            let escaped = Self.jsonEscape(t)
                            Self.writeSSEEvent(channel: channel, event: "content_block_delta",
                                data: "{\"type\":\"content_block_delta\",\"index\":\(textBlockIndex),\"delta\":{\"type\":\"text_delta\",\"text\":\"\(escaped)\"}}")

                        case .error(let e):
                            let escaped = Self.jsonEscape(e)
                            Self.writeSSEEvent(channel: channel, event: "error",
                                data: "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"\(escaped)\"}}")

                        case .done:
                            // Close any open blocks
                            if thinkingBlockOpen {
                                Self.writeSSEEvent(channel: channel, event: "content_block_stop",
                                    data: "{\"type\":\"content_block_stop\",\"index\":0}")
                            }
                            if textBlockOpen {
                                Self.writeSSEEvent(channel: channel, event: "content_block_stop",
                                    data: "{\"type\":\"content_block_stop\",\"index\":\(textBlockIndex)}")
                            }
                            // message_delta with stop_reason
                            Self.writeSSEEvent(channel: channel, event: "message_delta",
                                data: "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":0}}")
                            // message_stop
                            Self.writeSSEEvent(channel: channel, event: "message_stop",
                                data: "{\"type\":\"message_stop\"}")

                        case .sessionID:
                            break
                        }
                    }
                },
                onLog: { message in
                    onLog?(LogEntry(
                        timestamp: Date(),
                        method: "POST",
                        path: "/v1/messages",
                        info: "",
                        statusCode: nil,
                        latency: nil,
                        isError: message.hasPrefix("Error"),
                        rawLine: message
                    ))
                },
                onComplete: { [weak channel] statusCode in
                    guard let channel else { return }
                    channel.eventLoop.execute {
                        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                        let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                        if !thinkingText.isEmpty {
                            onLog?(LogEntry(timestamp: startTime, method: "POST", path: "/v1/messages",
                                            info: "", statusCode: nil, latency: nil, isError: false,
                                            rawLine: "💭 \(thinkingText)"))
                        }
                        if !responseText.isEmpty {
                            onLog?(LogEntry(timestamp: startTime, method: "POST", path: "/v1/messages",
                                            info: "", statusCode: nil, latency: nil, isError: false,
                                            rawLine: "← \(responseText)"))
                        }
                        onLog?(LogEntry(timestamp: startTime, method: "POST", path: "/v1/messages",
                                        info: "", statusCode: statusCode, latency: "\(ms)ms",
                                        isError: statusCode >= 400,
                                        rawLine: "← \(statusCode) (\(ms)ms)"))
                    }
                }
            )
        } else {
            // Non-streaming: collect all frames, then return complete JSON
            var responseText = ""
            var thinkingText = ""

            process.start(
                provider: provider,
                prompt: prompt,
                sessionID: nil,
                model: body.model,
                systemPrompt: systemPrompt,
                onFrame: { frame in
                    switch frame {
                    case .text(let t): responseText += t
                    case .thinking(let t): thinkingText += t
                    default: break
                    }
                },
                onLog: { message in
                    onLog?(LogEntry(
                        timestamp: Date(),
                        method: "POST",
                        path: "/v1/messages",
                        info: "",
                        statusCode: nil,
                        latency: nil,
                        isError: message.hasPrefix("Error"),
                        rawLine: message
                    ))
                },
                onComplete: { [weak channel] statusCode in
                    guard let channel else { return }
                    channel.eventLoop.execute {
                        var contentArray: [[String: Any]] = []
                        if !thinkingText.isEmpty {
                            contentArray.append(["type": "thinking", "thinking": thinkingText, "signature": ""])
                        }
                        contentArray.append(["type": "text", "text": responseText])

                        let responseDict: [String: Any] = [
                            "id": msgID,
                            "type": "message",
                            "role": "assistant",
                            "content": contentArray,
                            "model": modelName,
                            "stop_reason": "end_turn",
                            "stop_sequence": NSNull(),
                            "usage": ["input_tokens": 0, "output_tokens": 0]
                        ]

                        let jsonData = (try? JSONSerialization.data(withJSONObject: responseDict, options: []))
                            ?? "{}".data(using: .utf8)!
                        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                        var headers = HTTPHeaders()
                        headers.add(name: "Content-Type", value: "application/json")
                        headers.add(name: "Access-Control-Allow-Origin", value: "*")
                        headers.add(name: "Content-Length", value: "\(jsonString.utf8.count)")
                        let respHead = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
                        channel.write(HTTPServerResponsePart.head(respHead), promise: nil)
                        var buf = channel.allocator.buffer(capacity: jsonString.utf8.count)
                        buf.writeString(jsonString)
                        channel.write(HTTPServerResponsePart.body(.byteBuffer(buf)), promise: nil)
                        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)

                        let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                        if !thinkingText.isEmpty {
                            onLog?(LogEntry(timestamp: startTime, method: "POST", path: "/v1/messages",
                                            info: "", statusCode: nil, latency: nil, isError: false,
                                            rawLine: "💭 \(thinkingText)"))
                        }
                        if !responseText.isEmpty {
                            onLog?(LogEntry(timestamp: startTime, method: "POST", path: "/v1/messages",
                                            info: "", statusCode: nil, latency: nil, isError: false,
                                            rawLine: "← \(responseText)"))
                        }
                        onLog?(LogEntry(timestamp: startTime, method: "POST", path: "/v1/messages",
                                        info: "", statusCode: statusCode, latency: "\(ms)ms",
                                        isError: statusCode >= 400,
                                        rawLine: "← \(statusCode) (\(ms)ms)"))
                    }
                }
            )
        }
    }

    private static func writeSSEEvent(channel: Channel, event: String, data: String) {
        let sseString = "event: \(event)\ndata: \(data)\n\n"
        var buf = channel.allocator.buffer(capacity: sseString.utf8.count)
        buf.writeString(sseString)
        channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buf)), promise: nil)
    }

    private static func jsonEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func writeAnthropicError(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        let escaped = Self.jsonEscape(message)
        let body = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"\(escaped)\"}}"
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        let ms = Int((requestStart.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        onLog?(LogEntry(
            timestamp: requestStart ?? Date(),
            method: "POST",
            path: "/v1/messages",
            info: "",
            statusCode: Int(status.code),
            latency: "\(ms)ms",
            isError: true,
            rawLine: "← \(status.code) \(message) (\(ms)ms)"
        ))
    }



    // MARK: - Models

    private func handleListModels(context: ChannelHandlerContext) {
        let models = ProviderProcess.listModels(for: provider)

        var dataArray: [[String: String]] = []
        for m in models {
            dataArray.append([
                "id": m.id,
                "type": "model",
                "display_name": m.displayName,
                "created_at": "2025-01-01T00:00:00Z"
            ])
        }

        let firstId = models.first?.id ?? ""
        let lastId = models.last?.id ?? ""
        let responseDict: [String: Any] = [
            "data": dataArray,
            "has_more": false,
            "first_id": firstId,
            "last_id": lastId
        ]

        let jsonData = (try? JSONSerialization.data(withJSONObject: responseDict, options: [])) ?? "{}".data(using: .utf8)!
        let body = String(data: jsonData, encoding: .utf8) ?? "{}"

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    // MARK: - Help

    private func writeHelp(context: ChannelHandlerContext, version: HTTPVersion) {
        let body: String
        if let url = Bundle.main.url(forResource: "help", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            body = content
        } else {
            body = "Help file not found."
        }
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        let head = HTTPResponseHead(version: version, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    // MARK: - Error / Preflight Responses

    private func writeCORSPreflight(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type")
        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func writeError(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        let body = "{\"error\":\"\(message)\"}"
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        let ms = Int((requestStart.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        let entry = LogEntry(
            timestamp: requestStart ?? Date(),
            method: "POST",
            path: "/",
            info: "",
            statusCode: Int(status.code),
            latency: "\(ms)ms",
            isError: true,
            rawLine: "← \(status.code) \(message) (\(ms)ms)"
        )
        onLog?(entry)
    }
}
