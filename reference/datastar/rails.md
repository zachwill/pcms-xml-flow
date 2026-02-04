# Using Ruby on Rails SSE with Datastar for Real-Time Updates

Datastar is a *hypermedia-first* frontend framework that lets your Rails backend drive the UI via HTML and Server-Sent Events (SSE). Unlike typical single-page apps, Datastar doesn’t need additional frontend frameworks – you send HTML fragments or SSE streams from Rails, and Datastar patches the DOM or updates reactive signals on the client.

This guide explains how to use **SSE in Rails (latest version)** for both on-demand responses and persistent streams, how to structure controllers to emit `datastar-patch-elements` and `datastar-patch-signals` events, and best practices for reliability, performance, and security in production.

## Enabling Server-Sent Events in Rails

Rails has built-in support for SSE through **ActionController::Live**. This module allows controller actions to stream data directly to the client. To set up an SSE endpoint in Rails:

- **Include the Live module:** In your controller, include `ActionController::Live` to enable streaming.
- **Set the content type:** Specify the response MIME type as `text/event-stream` to indicate an SSE stream.
- **Stream data using SSE class:** Rails provides an `ActionController::Live::SSE` helper. You initialize it with `response.stream` and optional parameters like default `event` name or `retry` interval. Then use `sse.write` to send events (it will format data as SSE-compliant text). Always call `sse.close` when done.

**Example – Basic SSE Controller in Rails:**

```ruby
class EventsController < ApplicationController
  include ActionController::Live

  def index
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Last-Modified'] = Time.now.httpdate  # avoid ETag buffering
    sse = SSE.new(response.stream, event: "message")       # default event name "message"
    begin
      sse.write({ message: "Hello from SSE" })             # sends an SSE with JSON data
    rescue ActionController::Live::ClientDisconnected
      # handle client disconnect if needed (e.g., log or clean up)
    ensure
      sse.close                                            # always close the stream when done
    end
  end
end
```

In the above code, the controller keeps the HTTP connection open and writes an event. We set `Last-Modified` to the current time to disable Rack’s ETag middleware which would otherwise buffer the response (ensuring events flush immediately as they are written). On the client side, Datastar (or a raw `EventSource`) will receive this event in real-time.

**Rails SSE under the hood:** Each call to `sse.write` formats the data as an SSE event and flushes it down `response.stream`. You can pass a Ruby object (which gets JSON-encoded) or a raw string. For example, `sse.write({name: "John"}, event: "greeting", id: 42)` will send an event like:

```bash
event: greeting
id: 42
data: {"name":"John"}
```

Rails will manage a separate thread for streaming so that the action can keep sending data without blocking other requests. However, you should still be mindful of threading (more on performance below).

## One-off SSE Responses vs. Persistent Streams

**Request/Response SSE (One-off):** In many cases, you will use SSE as the response to a user’s action. For example, clicking a button might trigger a GET or POST request that your Rails controller handles by **immediately streaming one or more SSE events and then closing the connection**. This is effectively a normal HTTP request/response cycle, except the response is a stream of events instead of a single HTML or JSON payload.

Datastar is designed to handle such responses seamlessly – it knows that a `text/event-stream` response may contain multiple events to apply. One SSE response can carry multiple updates (e.g. patching several elements and signals together).

**Persistent Streaming SSE:** Alternatively, you can keep an SSE connection open for ongoing updates. This is useful for real-time features (notifications, live dashboards, etc.) where the server pushes updates asynchronously. In Rails, a controller action can enter a loop or subscribe to some event source and continuously `sse.write` new events.

```ruby
def live_feed
  response.headers['Content-Type'] = 'text/event-stream'
  response.headers['Cache-Control'] = 'no-cache'     # prevent caching of SSE stream
  response.headers['X-Accel-Buffering'] = 'no'       # disable nginx buffering for SSE
  sse = SSE.new(response.stream, event: "update", retry: 500)

  begin
    loop do
      data = { timestamp: Time.now.to_s }
      sse.write(data)                                # send an "update" event with JSON data
      sleep 5                                        # simulate periodic updates
    end
  rescue ActionController::Live::ClientDisconnected
    # client disconnected (browser closed or navigated away)
  ensure
    sse.close
  end
end
```

In this persistent stream example, the action keeps sending an `"update"` event every 5 seconds until the client disconnects. We set a `retry: 500` ms so that the client (EventSource) will attempt reconnection after 0.5s if the connection drops. Datastar can maintain a persistent SSE connection as well (behavior can be configured with `openWhenHidden` for background tabs).

**Note:** Browser limits apply to SSE connections. Most browsers allow only ~6 open HTTP/1.1 SSE connections per domain (shared across tabs). Using HTTP/2 mitigates this with a higher stream limit (often 100 or more). In practice, design your app to use as few concurrent SSE connections as needed (usually one per client for broad updates, plus transient ones for requests).

## Structuring Controllers for Datastar SSE Events

Datastar’s client listens for specific SSE event types to know how to update the page. The two primary event types are:

- `datastar-patch-elements`
- `datastar-patch-signals`

Your Rails controllers should emit these events to integrate with Datastar’s reactive model:

- **`datastar-patch-elements`:** Instructs the client to morph or replace a section of the DOM. The event’s data typically contains an HTML fragment and optional directives (like a target selector or mode). Datastar will find the element(s) by ID (or CSS selector) and patch them. You can also specify modes such as `append`, `prepend`, `replace`, etc.

- **`datastar-patch-signals`:** Instructs the client to update one or more reactive *signals* (Datastar’s client-side state variables). The event data includes a JSON object of signal names and values. Datastar will merge these into its global signals store, creating new signals if needed and triggering any bound UI updates. Setting a signal’s value to `null` removes that signal.

### Using the Datastar Ruby SDK

To simplify emitting these events, you can use the official **Datastar Ruby SDK** gem. Add:

```ruby
gem 'datastar'
```

…to your Gemfile and initialize a `Datastar` dispatcher in your controller. This SDK provides high-level methods to send Datastar-specific SSE events without manually formatting them.

```ruby
class QuizController < ApplicationController
  include ActionController::Live

  def ask_question
    datastar = Datastar.new(request: request, response: response)
    # One-off response: patch an element and a signal, then close
    datastar.patch_elements(render_to_string(partial: "question"))  # insert question HTML
    datastar.patch_signals(score: 0)                                # initialize a signal
  end

  def stream_updates
    datastar = Datastar.new(request: request, response: response)
    datastar.stream do |sse|
      # Send initial content
      sse.patch_elements("<div id='status'>Connected.</div>")

      # Send multiple updates over time
      5.times do |i|
        sleep 1
        sse.patch_elements("<div id='status'>Update ##{i + 1}</div>")
        sse.patch_signals(latestUpdate: i + 1)
      end
    end
    # stream block automatically closes the stream when done
  end
end
```

In `ask_question`, we use `datastar.patch_elements` and `.patch_signals` for a **one-off** SSE response. The SDK takes care of setting `Content-Type: text/event-stream` and formatting SSE event lines.

In `stream_updates`, `datastar.stream do |sse| ... end` opens a persistent SSE connection and sends multiple element and signal patches over time.

### Manual Formatting (if not using SDK)

You can also write SSE events yourself:

```ruby
response.headers['Content-Type'] = 'text/event-stream'
sse = SSE.new(response.stream)

sse.write("<div id='notice'>Hello</div>", event: "datastar-patch-elements")
sse.write('{ "welcomeMessage": "Hello" }', event: "datastar-patch-signals")

sse.close
```

Make sure strings are properly formatted:
- For `datastar-patch-elements`, include the HTML as the event data.
- For `datastar-patch-signals`, send a JSON object string.

## Datastar SSE Event Types: Patch Elements vs Patch Signals

To integrate tightly with Datastar’s reactive model, it’s important to understand when to use element patches vs signal patches (or both):

- **Use `datastar-patch-elements` for structural or content changes:**  
  Insert, replace, or remove chunks of HTML in the DOM (components, list items, modals, etc.). In Rails, this often means rendering a partial or view fragment and sending it. Ensure the fragment’s top-level elements have IDs that exist in the current DOM (so Datastar knows what to replace). If an element with that ID is not yet in the DOM, you can use a mode like `append`/`prepend` with a selector, or render a placeholder element.

  *Tip:* Preserve client-side state (like input focus or CSS animations) by patching only necessary parts. Morphing will keep child elements/state intact when IDs match.

- **Use `datastar-patch-signals` for reactive state updates:**  
  Signals are global state variables (accessible via `$signalName` in the DOM). If your update is purely data (not new markup), patch signals. Elements referencing the signal (via `data-text`, `data-show`, `data-bind`, etc.) auto-update.

  *Tip:* Datastar applies signal payloads as a JSON merge patch (RFC 7396). Nested objects work (e.g. `{ user: { name: "Alice" } }`). If you only want to set a signal if it’s not already present, use `onlyIfMissing` (supported by the Ruby SDK options).

Often you will use both: after a form submission, patch HTML (updated table) and patch signals (flash message, computed value). SSE allows multiple events in one response.

## Setting Up Reliable SSE Connections (Headers & Config)

To ensure SSE works consistently, especially in production, pay attention to HTTP headers and server/proxy configuration:

- **Content-Type:**  
  Set `Content-Type: text/event-stream; charset=utf-8` on SSE responses.

- **No Caching:**  
  Set `Cache-Control: no-cache` so browsers/proxies don’t cache the stream.

- **Disable Response Buffering:**  
  Proxies (Nginx, CDNs) may buffer responses, breaking real-time delivery. Set:  
  `X-Accel-Buffering: no`  
  Also consider bypassing ETag buffering (e.g., the `Last-Modified` trick) for SSE endpoints.

- **Connection Keep-Alive:**  
  SSE relies on persistent connections. Avoid setting `Content-Length`, and only close intentionally via `sse.close`.

- **Flushing / Heartbeats:**  
  The Rails SSE helper flushes internally. If writing manually, flush after each event. A periodic comment line (e.g., `":\n
"`) can serve as a heartbeat for infrequent updates.

- **CORS (if needed):**  
  If SSE is cross-origin, configure CORS appropriately, and use `EventSource` credential settings if required.

## Security Considerations for SSE

Treat SSE endpoints like any other HTTP endpoint:

- **Authentication & Authorization:**  
  Restrict streams with normal Rails auth (cookies, JWT, etc.). Verify permissions before streaming.

- **Input Handling / XSS:**  
  If you patch HTML that includes user-generated content, ensure it’s sanitized/escaped. Datastar patches HTML directly into the DOM, so unsafe tags/attributes could execute.

- **Sensitive Data Exposure:**  
  Don’t broadcast private data to the wrong audience. Consider per-user or per-channel streams and server-side filtering.

- **Denial of Service:**  
  SSE keeps connections open; attackers might open many connections. Mitigate with rate limits, connection caps per IP/user, monitoring, and possibly stream tokens.

- **HTTPS:**  
  Serve SSE over HTTPS for sensitive data. Consider `Cache-Control: no-transform` if intermediary proxies might alter the stream.

## Performance and Deployment Best Practices

- **Threading and Workload:**  
  Each open SSE connection occupies a thread in typical Rails deployments (e.g., Puma). Ensure your thread pool sizing matches expected concurrency, plus headroom for normal requests.

- **Avoid Blocking Operations:**  
  Don’t do heavy work inside the streaming loop thread. Offload to background jobs or restructure work so the SSE loop remains responsive.

- **Event Frequency:**  
  Avoid excessive event rates. Consider batching or sending “fat patches” (full state for a section) instead of many tiny events.

- **Heartbeat and Reconnect:**  
  EventSource reconnects automatically. Design streams to be stateless/recoverable (idempotent, full-state events), or implement `Last-Event-ID` if you need resumability.

- **Proxy and Timeout Issues:**  
  Many load balancers close idle connections (often ~60s). Either configure timeouts, or send heartbeat comments periodically, or use HTTP/2 where applicable. (Infrastructure defaults vary: e.g., Heroku has inactivity timeouts; Nginx may need `proxy_read_timeout` adjustments.)

- **Testing and Monitoring:**  
  Load-test SSE endpoints, monitor memory/threads/file descriptors, and handle disconnect exceptions cleanly.

- **Deployment Configurations:**  
  Puma is a good choice for SSE. Prefork-only servers (e.g., Unicorn) are a poor fit. In multi-node deployments, reconnects may hit a different node—design state accordingly (stateless, shared pub/sub, etc.). For broadcasting events across nodes, use pub/sub (e.g., Redis, Postgres LISTEN/NOTIFY).

## Conclusion

Using **Server-Sent Events in Rails with Datastar** unlocks real-time, reactive user interfaces without a heavy front-end framework. The Rails controller sends HTML and state updates, and Datastar’s small JavaScript library handles DOM morphing and signal updates.

Key steps:

- **Setup Rails endpoints for SSE:** include `ActionController::Live`, set `Content-Type: text/event-stream`, stream events using Rails SSE tools. Use the Datastar Ruby SDK to emit `datastar-patch-elements` / `datastar-patch-signals`.
- **Structure responses to drive the UI:** patch elements for DOM changes, patch signals for state changes — or combine them.
- **Configure for reliability:** `no-cache`, disable buffering, send heartbeats if needed, handle reconnections gracefully.
- **Mind security and performance:** authenticate streams, avoid data leaks, size thread pools, and test under load.

By following these practices, your Rails app can push updates to the Datastar-driven frontend in real time, keeping the UI in sync with server state while staying hypermedia-driven.

## Sources

- Rails API — ActionController::Live::SSE  
  https://api.rubyonrails.org/classes/ActionController/Live/SSE.html

- Datastar documentation (guides/reference)  
  https://data-star.dev/  
  https://data-star.dev/reference/sse_events  
  https://data-star.dev/guide/backend_requests  
  https://data-star.dev/guide/reactive_signals  
  https://data-star.dev/how_tos/prevent_sse_connections_closing

- Rails SSE examples / buffering notes  
  https://medium.com/@thilonel/how-to-use-rails-actioncontroller-live-sse-server-sent-events-d9a04a286f77  
  https://pragmaticpineapple.com/using-server-sent-events-to-stream-data-in-rails/

- MDN — Using server-sent events  
  https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events

- Proxy/buffering troubleshooting discussion  
  https://stackoverflow.com/questions/69427980/cache-problem-server-side-events-work-in-localhost-not-in-production-enviromen

- Datastar Ruby SDK README  
  https://github.com/starfederation/datastar-ruby
