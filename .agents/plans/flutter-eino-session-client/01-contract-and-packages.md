# W1 — Contract and package foundation

Goal: establish independently consumable packages and the versioned boundary before behavior implementation. Prerequisite: overview operating context and initial maintainer decision. No backwards compatibility layer, migration or feature flag is required.

## Dependency contract

| Dependency | Exact selected baseline | Evidence and role |
| --- | --- | --- |
| `ag_ui` | Public Git `https://github.com/mattsp1290/ag-ui.git`, ref `691ab5e3846ad5957d1b04a9237167f5496c6232`, path `sdks/community/dart` | PR #46 final head; pubspec 0.3.0. Fresh anonymous Pub resolution, exact lockfile/cache source, standalone analysis and public bounds/cancellation probe passed September 10. Full URL/ref/path identifies this fork dependency; no pub.dev equivalence or merge claim. |
| `http` | Hosted `1.6.0` | Exported `AbortableRequest` and `abortTrigger`; default transport requires a client that implements abort support. |
| `github.com/mattsp1290/eino-agent` | `v0.3.4-0.20260908141855-99a87b8cb1ac`, commit `99a87b8cb1ac5f11cf39c44f352b7b7849e8d97f` | Proxy metadata and checksum-backed module download verified. Includes bounded watch plus write-deadline fixes absent in earlier watch pin `3749323aace4`. |
| `github.com/mattsp1290/eino-agui` | `v0.1.1` | Selected Eino module dependency. Public AG-UI conversion/emission. |
| AG-UI Go module | `github.com/ag-ui-protocol/ag-ui/sdks/community/go v0.0.0-20260624151131-d2049debabd9` | Selected Eino module dependency, real SSE encoder. |
| Eino | `github.com/cloudwego/eino v0.8.13` | Selected Eino module dependency; no unrequested model/provider upgrade. |
| Go | `1.26.8`, module floor `1.26.3` | Resolved local toolchain supports upstream floor. Declare CI toolchain explicitly. |
| Flutter / Dart | Flutter `3.47.1` / its bundled Dart `3.13.1` | Initial proposed validation matrix (not yet executed): same version on Linux and macOS. Declare package SDK floor `>=3.13.1 <4.0.0`; widget Flutter floor `>=3.47.1`. Do not claim older SDK support. |

The source request's v0.3.3 is a research baseline, not a requirement to freeze that version. Its cursor-based legacy transport cannot be advertised as the new bounded watch API. The newer pin is deliberate and recorded in the response. Do not track an unpinned branch. Validate complete dependency resolution in W1; a metadata download alone is not a consumer build.

## Exact proposed layout

Every path and symbol below is **new/proposed**, except existing root `README.md`, `.gitignore`, and `LICENSE`. The existing insertion point for all new top-level directories is repository root `.`. Within each new directory, descendants are created by that work package. In package rows below, short `lib/...` and `test/...` paths are relative to the first named package directory, not repository root. No listed implementation path exists during planning.

| New path rooted at `.` | Purpose / proposed symbols |
| --- | --- |
| `packages/ag_ui_view_state/pubspec.yaml`, `lib/ag_ui_view_state.dart`, `lib/src/view_state.dart` | Pure Dart package; `AgentViewState`, `MessageView`, `ToolActivityView`, `ConnectionPhase`, `RunPhase`, `ViewFailure`, `ViewLimits`. |
| `packages/ag_ui_view_state/lib/src/controller.dart`, `lib/src/reducer.dart` | `AgentViewController`, `EventViewReducer`; controller owns projection/listener lifecycle, reducer is synchronous and independently testable. |
| `packages/ag_ui_view_state/lib/src/transport.dart`, `lib/src/http_transport.dart`, `lib/src/ag_ui_post_adapter.dart` | `RequestTransport`, `RequestOperation`, `HttpRequestTransport`, `AgUiPostAdapter`; byte transport and generic caller-owned-history adapter. |
| `packages/ag_ui_view_state/test/` | New reducer, bounds, lifecycle, HTTP and conformance tests named in W2/W3/W5. |
| `packages/ag_ui_widgets/pubspec.yaml`, `lib/ag_ui_widgets.dart`, `lib/src/transcript_view.dart`, `lib/src/tool_activity_list.dart`, `lib/src/agent_input.dart`, `test/` | `TranscriptView`, `ToolActivityList`, `AgentInput`; depends only on Flutter and core. |
| `packages/eino_session_client/pubspec.yaml`, `lib/eino_session_client.dart`, `lib/src/session_adapter.dart`, `lib/src/watch_projection.dart`, `lib/src/session_contract.dart`, `test/` | Pure Dart optional package; `EinoSessionAdapter`, `WatchProjection`, `EinoSessionContract`, typed safe watch state. Depends only on core and SDK/HTTP as needed. |
| `analysis_options.yaml`, `tool/verify.sh`, `tool/check_boundaries.dart` | Shared analysis settings, explicit per-package verification and architecture/dependency check. |
| `docs/integration-contract.md`, `docs/ownership.md` | Versioned API and maintainer/boundary record. |

W4/W5 declare remaining new paths. All public symbol names here are design proposals, not upstream APIs. Public barrels export only supported types. Never import `package:ag_ui/src/...` in the new packages.

## API contract

`AgentViewController` exposes immutable current state, synchronous listener registration returning an unsubscribe callback, and idempotent asynchronous disposal. Avoid a broadcast stream that silently accumulates a queue for each paused UI subscriber. Host listeners must be fast; listeners receive the latest immutable state and cannot mutate controller collections. Reentrant actions are deferred to a bounded controller operation slot or rejected as busy. Listener exceptions are isolated and classified without recording exception content.

Adapters feed typed SDK events or typed safe replacements to the controller. The reducer does not own HTTP, widget callbacks, auth or Eino-specific JSON. Generic code accepts SDK `SimpleRunAgentInput`, preserving host-owned message/tool/context/state/forwardedProps data at the request boundary. Never reconstruct submitted history from the restricted display projection. Server-owned input uses a separate method accepting only new text and a host session identity.

`RequestTransport.open` returns a `RequestOperation` immediately, before response headers. An operation exposes a response future and idempotent asynchronous abort. Responses expose status, content type and a single-subscription byte stream. Header creation and route mapping are injected per operation. `HttpRequestTransport` uses `http.AbortableRequest`; requests and body subscriptions are independently cancellable. Injection is borrowed by default; an explicit owned factory closes its own client on transport disposal. SDK parser resources are locally owned: construct and retain a separate owned `http.Client`, inject it into a parser-only `SseClient`, and never give that wrapper the borrowed host transport client. Cancel the parser subscription, call `SseClient.close()` and independently close the retained parser HTTP client on every exit. At the researched pin `SseClient.close()` does not close its HTTP client. Test both closures and borrowed-client preservation. Never call its automatic `connect` path.

The generic adapter also exposes a new optional synchronous `onProtocolEvent(BaseEvent event)` host callback for canonical caller-owned history, separate from retained view state. It receives existing SDK response events in wire order before projection and terminal cleanup. The callback may retain host-owned canonical messages/tool calls/results at its own responsibility; the library retains no second event history and never logs callback/event content. It is opt-in and intended for host integration, never automatically forwarded to widgets. Callback errors fail the operation with a fixed hostCallbackFailed category and trigger request abortion. Reentrant adapter actions are rejected as busy or scheduled by the host; old generations and disposed adapters cannot invoke it. This seam does not authorize execution/approval and the Eino watch adapter does not expose a raw provider-state channel.

No protocol classes are copied. Public `Encoder().encodeRunAgentInput`, `SseClient.parseStream`, `EventStreamAdapter.fromSseStream`, `MessagesSnapshotEvent`, `TextMessage*Event`, `ToolCall*Event`, `Run*Event` are the inspected APIs. SDK maintainer: Matt, explicitly confirmed by the user. If a missing generic parser/JSON-patch capability appears, its owner is Matt in `$AG_UI_ROOT/sdks/community/dart`; the shared package must not implement a substitute.

## Acceptance

Create independent pubspecs with consistent SDK/Git/http pins. Use relative path dependencies only for local development via untracked/generated `pubspec_overrides.yaml`; distributed pubspecs must contain public Git refs as described in W5. During initial staged implementation, same-repository relative dependencies may be used until W5 replaces them for consumption. Never use absolute paths. Modify `.gitignore` to retain example/package resolution locks used by CI and ignore transient overrides.

The SDK readiness prerequisite is satisfied at the exact fork pin above; preserve it in every package. W1 still compiles the planned public API seams and resolves the complete package graph. Go graph research can use a disposable external module; W5 owns the retained harness module.

Run `dart pub get`, `dart analyze` in each pure Dart package and `flutter pub get`, `flutter analyze` in the widget package. Use the Dart bundled with the selected Flutter. Resolve the external Go harness graph with `GOWORK=off` and no consumer replace/vendor directory. W1 is accepted when all public SDK seams compile, package dependency direction is checked, the selected module graph is recorded, and the new APIs cannot expose application-specific types. No publishing is performed in this work package.

## Verified SDK byte-parser contract and provenance

At `691ab5e3846ad5957d1b04a9237167f5496c6232`, exported `SseClient` accepts positive exact `maxDataCodeUnits` D and optional `maxLineCodeUnits` L. Set D=1,048,576 and L=D+7=1,048,583 for this plan; set `EventStreamAdapter.maxDataCodeUnits` to the same D. L counts the complete decoded UTF-16 line including field prefixes/spaces, excluding CR/LF and the SDK's legacy initial BOM removals. Supplementary characters count twice. Both limits must fit `1..9007199254740991`; omitted L requires D+7 to fit too. Aggregate data counts newline separators, and event values separately obey D.

Line overflow fails at decoded L+1 before newline/EOF, including comment/unknown-field lines. Malformed/truncated UTF-8 and parser errors terminate the parse call, cancel its source and discard partial state; complete preceding messages remain delivered. Errors are content-free `FormatException` values with no source/offset. The SDK internally bounds decoder slices and framing; do not add local parsing. Producer-owned byte chunks/queues and consumer-retained events remain outside the SDK's internal payload bound, so the shared transport/reducer bounds still apply. `SseClient.close()` still does not close its HTTP client; retain the explicit parser-client ownership rule above.

Verification on September 10: new external consumer and new PUB_CACHE; public HTTPS Git resolution with Git system/global credentials/config and interactive prompts disabled; no token variables, path override or workspace. The lock's `resolved-ref` equals the full selected SHA, and package configuration points into the new cache's matching Git checkout. Flutter 3.47.1 / bundled Dart 3.13.1 ran `dart pub get`, `dart analyze` and `dart run bin/verify_sse_byte_bounds.dart`, all exit 0. The probe was copied unchanged from the selected commit's `sdks/community/dart/tool/verify_sse_byte_bounds.dart`; its Git blob and safe output are in [sdk-pin-verification.json](sdk-pin-verification.json).

Reproduce using the selected SDK's `TEST_GUIDE.md` section “Fresh public immutable dependency”, with SSE_PIN set to this full SHA and the fork URL above. The owner response records fuller SDK UTF-8/framing/VM/Chrome/diagnostic tests and the latest reviewed pin; use its topmost September 9 completion record, not the historical e3a20a2 implementation pin lower in that response. The September 10 consumer check proves the blocker contract, not the future shared Go/Dart/Flutter integration suite. SDK example source is an inspected pattern, not an added dependency or authorization to adopt its extra capabilities.
