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

        guard head.method == .POST else {
            writeError(context: context, status: .notFound, message: "Not found")
            return
        }

        struct GenerateBody: Decodable {
            let prompt: String
            let session_id: String?
        }

        let bytes = Data(bodyBuffer.readableBytesView)
        guard let body = try? JSONDecoder().decode(GenerateBody.self, from: bytes),
              !body.prompt.isEmpty else {
            writeError(context: context, status: .badRequest, message: "prompt is required")
            return
        }

        // SSE response headers
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: "keep-alive")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        let responseHead = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
        context.writeAndFlush(wrapOutboundOut(.head(responseHead)), promise: nil)

        var bodyDict: [String: Any] = ["prompt": body.prompt]
        if let sid = body.session_id { bodyDict["session_id"] = sid }
        let requestBodyJSON = (try? JSONSerialization.data(withJSONObject: bodyDict, options: .prettyPrinted))
            .flatMap { String(data: $0, encoding: .utf8) }

        let channel = context.channel
        let startTime = requestStart ?? Date()
        let onLog = self.onLog

        onLog?(LogEntry(
            timestamp: startTime,
            method: "POST",
            path: "/",
            info: "",
            statusCode: nil,
            latency: nil,
            isError: false,
            rawLine: "→ \(body.prompt)"
        ))

        var responseText = ""
        var thinkingText = ""

        let process = ProviderProcess()
        activeProcess?.kill()
        activeProcess = process

        process.start(
            provider: provider,
            prompt: body.prompt,
            sessionID: body.session_id,
            systemPrompt: systemPrompt,
            onFrame: { [weak channel] frame in
                switch frame {
                case .text(let t): responseText += t
                case .thinking(let t): thinkingText += t
                default: break
                }
                guard let channel else { return }
                let data = Self.sseString(for: frame)
                channel.eventLoop.execute {
                    var buf = channel.allocator.buffer(capacity: data.utf8.count)
                    buf.writeString(data)
                    channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buf)), promise: nil)
                }
            },
            onLog: { message in
                onLog?(LogEntry(
                    timestamp: Date(),
                    method: "POST",
                    path: "/",
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
                        onLog?(LogEntry(
                            timestamp: startTime,
                            method: "POST",
                            path: "/",
                            info: "",
                            statusCode: nil,
                            latency: nil,
                            isError: false,
                            rawLine: "💭 \(thinkingText)"
                        ))
                    }
                    if !responseText.isEmpty {
                        onLog?(LogEntry(
                            timestamp: startTime,
                            method: "POST",
                            path: "/",
                            info: "",
                            statusCode: nil,
                            latency: nil,
                            isError: false,
                            rawLine: "← \(responseText)"
                        ))
                    }
                    onLog?(LogEntry(
                        timestamp: startTime,
                        method: "POST",
                        path: "/",
                        info: "",
                        statusCode: statusCode,
                        latency: "\(ms)ms",
                        isError: statusCode >= 400,
                        rawLine: "← \(statusCode) (\(ms)ms)",
                        requestBody: requestBodyJSON
                    ))
                }
            }
        )
    }

    // MARK: - SSE Helpers

    private static func sseString(for frame: SSEFrame) -> String {
        switch frame {
        case .sessionID(let sid):   return sseJSON(["session_id": sid])
        case .thinking(let t):      return sseJSON(["thinking": t])
        case .text(let t):          return sseJSON(["text": t])
        case .error(let e):         return sseJSON(["error": e])
        case .done:                 return "data: [DONE]\n\n"
        }
    }

    private static func sseJSON(_ dict: [String: String]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "data: \(json)\n\n"
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
        headers.add(name: "Access-Control-Allow-Methods", value: "POST, OPTIONS")
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
