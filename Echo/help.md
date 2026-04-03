# Echo

## POST /

Send a prompt to the AI provider. Returns a Server-Sent Events (SSE) stream.

### Request headers

- `Content-Type: application/json`

### Request body (JSON)

```json
{
  "prompt": "Your message here",
  "session_id": "optional — omit to start a new session, include to resume"
}
```

### Response (text/event-stream)

Each event is a `data:` line containing JSON:

- `{"session_id": "..."}` — session ID for this conversation; pass it back to resume
- `{"thinking": "..."}` — incremental reasoning text (provider-dependent)
- `{"text": "..."}` — incremental response text
- `{"error": "..."}` — error message
- `[DONE]` — stream complete

### Error responses

Non-streaming errors are returned as JSON with an appropriate HTTP status code:

```json
{ "error": "prompt is required" }
```

### CORS

All endpoints include `Access-Control-Allow-Origin: *`, so this server can be called directly from a browser.

### Example

```sh
# Start a new conversation
curl -N http://localhost:3000/ \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello!"}'

# Resume a conversation
curl -N http://localhost:3000/ \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What did I just say?", "session_id": "<session_id from previous response>"}'
```

Expected response:

```
data: {"session_id":"abc123"}
data: {"thinking":"The user said hello, I should greet them back."}
data: {"text":"Hello"}
data: {"text":"! How can I help you today?"}
data: [DONE]
```

## System prompt

Echo injects a minimal base system prompt to ensure the underlying CLI tool behaves correctly. Beyond that, you are responsible for defining the assistant's persona and behavior — Echo does not manage this for you.

It is also a good idea to specify the expected response format and structure in your system prompt. Without this, the model may return responses in a format or shape that doesn't match what your application expects.

## GET /help

Returns this document.
