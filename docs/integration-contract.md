# Integration contract

## Package boundaries

`ag_ui_view_state` depends on the public `ag_ui` package and `http`. It has no
Flutter or Eino dependency. `ag_ui_widgets` depends on Flutter and the core view
package. `eino_session_client` is optional and depends on the core package,
public AG-UI decoding, and the request transport. No package imports private
AG-UI sources, application state frameworks, Go FFI, or host models.

The supported SDK tuple is `https://github.com/mattsp1290/ag-ui.git`, path
`sdks/community/dart`, commit
`691ab5e3846ad5957d1b04a9237167f5496c6232`. SSE data is limited to 1,048,576
UTF-16 code units and decoded lines to 1,048,583 code units.

## Generic caller-owned history

`AgUiPostAdapter.start` accepts the SDK's `SimpleRunAgentInput`, encodes the
whole value with the public SDK encoder, and performs one POST. It never retries
because another POST may execute the agent again. EOF without a terminal event
is incomplete. A successful or interrupted `RUN_FINISHED` is committed before
the response body is aborted; an interrupt outcome becomes `RunPhase.paused`
with the fixed status “Waiting for host action.”

The optional synchronous `onProtocolEvent` callback receives decoded SDK events
in wire order before projection. A host may use it to maintain canonical
messages, tool-call arguments, and tool results for the next request. That data
is host-owned and can be sensitive. It never enters widgets or the restricted
view state. Callback failures abort the request with the content-free
`hostCallbackFailed` classification.

## Eino server-owned sessions

`EinoSessionContract` builds fresh authorized watch, admission, and interrupt
requests and decodes the bounded admission acknowledgement. The shared adapter
does not define routes, store credentials, trust a returned cross-origin URL,
or authorize a user for a session.

`connect` opens a fresh GET and atomically commits each
`MESSAGES_SNAPSHOT`/`STATE_SNAPSHOT` pair. A reconnect sends no cursor or
`Last-Event-ID`, replaces the window, and never appends replacement text.
`start` accepts one new text string and sends exactly the contract-built
admission request. Lost admission acknowledgement becomes `outcomeUnknown`; it
is never re-posted. Only the exact acknowledged run ID can settle the local
submission. `resetSubmissionTracking` clears an unresolved local binding and
does not mutate server state.

Run status `interrupted` is authoritative Eino cancellation and differs from
the generic `paused` outcome. Interrupt response success is only an
acknowledgement; the watch remains authoritative.

## Ownership and disposal

Request operations have independent abort triggers. `HttpRequestTransport`
preserves a borrowed client and closes only a client created by its owned
constructor. Adapters own subscriptions, timers, parser wrappers, and parser
HTTP clients. Widgets own only controllers/focus nodes they create. Hosts own
the injected controller, adapter lifecycle, routes, authentication, canonical
history, and every action callback.

The view retains only user/assistant text, stable message and tool identity,
safe phases, truncation/staleness/unavailability flags, and content-free failure
categories. It does not retain request inputs, provider state, arbitrary
metadata, tool payloads, encrypted reasoning, interrupt payloads, or raw
exceptions.
