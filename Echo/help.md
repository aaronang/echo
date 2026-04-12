# Echo

## POST /v1/messages

Anthropic Messages API-compatible endpoint. This is the recommended way to interact with Echo — it works with Anthropic SDKs, LangGraph, and any tool that speaks the Anthropic Messages protocol.

### Request headers

- `Content-Type: application/json`
- `X-Session-ID: <id>` *(optional)* — resume a previous session (see [Sessions](#sessions))

### Request body (JSON)

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 8096,
  "messages": [
    { "role": "user", "content": "Hello!" }
  ],
  "stream": true
}
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| model | string | No | Model name (passed through but does not change which provider Echo uses) |
| max_tokens | integer | No | Maximum tokens in the response |
| messages | array | Yes | Array of `{"role": "user" |
| system | string | No | System prompt override |
| stream | boolean | No | true for streaming SSE, false for a single JSON response (default: false) |

### Streaming response (`stream: true`)

Returns `Content-Type: text/event-stream` with named SSE events:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-20250514","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":0,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"! How can I help you?"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":0}}

event: message_stop
data: {"type":"message_stop"}

event: session
data: {"type":"session","session_id":"<id>"}
```

If a session ID is available, a custom `event: session` event is emitted after `message_stop` (see [Sessions](#sessions)).

When the provider returns thinking/reasoning, a thinking content block (index 0) is emitted before the text block:

```
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me consider..."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
```

### Non-streaming response (`stream: false`)

Returns `Content-Type: application/json`:

```json
{
  "id": "msg_...",
  "type": "message",
  "role": "assistant",
  "content": [
    { "type": "text", "text": "Hello! How can I help you?" }
  ],
  "model": "claude-sonnet-4-20250514",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": { "input_tokens": 0, "output_tokens": 0 }
}
```

If reasoning was produced, a `thinking` block appears before the `text` block:

```json
{
  "content": [
    { "type": "thinking", "thinking": "Let me consider...", "signature": "" },
    { "type": "text", "text": "Hello! How can I help you?" }
  ]
}
```

### Error responses

Errors follow the Anthropic error format:

```json
{ "type": "error", "error": { "type": "invalid_request_error", "message": "..." } }
```

### CORS

All endpoints include `Access-Control-Allow-Origin: *`, so this server can be called directly from a browser.

### Examples

#### curl — streaming

```sh
curl -N http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "stream": true,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

#### curl — non-streaming

```sh
curl http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

#### Python — LangGraph / ChatAnthropic

Echo is compatible with Anthropic's Python SDK and LangChain's `ChatAnthropic`. Point the `base_url` at your Echo server:

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="claude-sonnet-4-20250514",
    base_url="http://localhost:3000",
    api_key="not-needed",       # Echo doesn't require an API key
)

response = llm.invoke("Hello!")
print(response.content)
```

This also works with LangGraph agents, tool-calling chains, and any integration that uses `ChatAnthropic` under the hood.

## Sessions

Echo supports multi-turn conversations using session IDs. The `X-Session-ID` header lets you resume a previous session so the provider retains conversation history.

### Flow

1. **First request** — send a message without `X-Session-ID`. The response will include a session ID.
2. **Subsequent requests** — include the session ID from the previous response in the `X-Session-ID` request header. Only the last user message is sent as the prompt; the provider recalls prior turns automatically.

### Where the session ID appears

| Mode | Location |
| --- | --- |
| Streaming (`stream: true`) | Custom SSE event `event: session` emitted **after** `message_stop`: `data: {"type":"session","session_id":"<id>"}` |
| Non-streaming (`stream: false`) | `X-Session-ID` response header |

### Example

#### Turn 1 — new session

```sh
curl -N http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "stream": true,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

The streaming response will include an SSE event like:

```
event: session
data: {"type":"session","session_id":"abc-123-def"}
```

#### Turn 2 — resume session

```sh
curl -N http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -H "X-Session-ID: abc-123-def" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "stream": true,
    "messages": [{"role": "user", "content": "What did I just say?"}]
  }'
```

The provider will have context from the first turn and can respond accordingly.

## System prompt

Echo passes the `system` field from the request directly to the underlying CLI provider without modification. Echo does not inject any system prompt of its own.

It is a good idea to specify the expected response format and structure in your system prompt. Without this, the model may return responses in a format or shape that doesn't match what your application expects.

## GET /help

Returns this document.