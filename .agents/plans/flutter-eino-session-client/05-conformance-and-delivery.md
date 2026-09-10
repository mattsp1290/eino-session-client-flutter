# W5 — Go conformance, plain examples and delivery

Goal: prove the cross-language contract on actual frames and expose usable packages. Prerequisites W1–W4. Start the Go harness after W1 to reveal contract defects early; W5 completion remains after adapters/widgets. No legacy deployment, data migration or feature flags.

## New change surface

All paths below are **new/proposed**, inserted under existing repository root `.`. Their child paths inherit the indicated new parent. Existing `README.md` and `.gitignore` are edited for usage and reproducibility.

- `conformance/go/go.mod`, `go.sum`, `cmd/fixture-server/main.go`, `internal/fixture/`, `internal/fixture/server_test.go`: standalone module consuming the pinned public Eino APIs, no workspace/local replace/vendor dependency.
- `conformance/fixtures/manifest.json`, `generic.sse`, `eino-watch.sse`, `eino-resync.sse`, `privacy.sse`: synthetic raw encoded fixture bytes and pinned-source provenance. Manifest records generator versions, scenario, deterministic seed, framing format and hashes; no real prompt or identity data.
- `tool/generate_fixtures.sh`, `tool/verify_fixtures.sh`, `tool/verify_public_consumer.sh`: generate, compare and fresh-consumer procedures. W1's `tool/verify.sh` invokes them in the defined gates.
- Core and Eino `test/go_frames_test.dart`, `test/live_server_test.dart` under their W1 parents: fixture decoding and cross-language live transport tests.
- `examples/generic_ag_ui/` and `examples/eino_session/`, each with new `pubspec.yaml`, `pubspec.lock`, `lib/main.dart`, `web/`, `integration_test/session_flow_test.dart`: two independent plain Flutter web hosts. Root is their existing insertion point; platform scaffolding is generated during implementation.
- `.github/workflows/ci.yml`, `docs/adoption.md`, `docs/release.md`: CI, honest consumer sketches and immutable distribution instructions.

## Real Go server and fixtures

Use selected Eino `examples/minimal-server` and public external-consumer watch tests as patterns; import public runtime/model/composition/session/store/watch/transport APIs in this standalone module rather than depending on another module's example main package or internal test helpers. Build a deterministic scripted model and a harmless mounted tool. A real orchestrator and SQLite store admit two sequential turns, run two distinct same-name tool calls, interrupt a paused run and reopen the store. No provider account, OAuth, network LLM, real user content or tool side effects are needed.

The fixture server exposes example-owned routes for generic POST and Eino new-message POST/watch/interrupt. Generic POST decodes SDK-compatible caller history, verifies both turns' supplied history and emits standard AG-UI events using the Go SDK/eino-agui emitter. It does not reinterpret that history as a server-owned Eino submission. The Eino routes call `runtime.Start` with one `runtime.UserMessage`, `transport.SessionWatchHandler`, and `transport.InterruptHandler`. Observe committed server history to prove a second turn sees prior turns once. Enforce example method/content/size checks and fake exact-session authorization before actions. Bind loopback only for development; use a same-origin reverse proxy or narrowly configured development CORS for Flutter web. CORS is an example host concern.

Capture bytes after real SSE encoding on an HTTP connection. Do not create the positive fixtures by concatenating hand-written JSON. Deterministic fixture scenarios can inject stable synthetic IDs/time through fixture-owned seams; normalize only nondeterministic allowed identity/time fields after capture with a documented deterministic mapping, then encode through the same Go SSE writer and record this normalization. Preserve envelope/payload casing and event ordering. Keep raw unnormalized captures temporary and synthetic. Malformed/oversize fixtures are explicit byte mutations of generated frames; record mutations in the manifest.

A fixture must exercise a durable baseline followed by generic new deltas, not just hand-built events. Eino fixtures separately show complete current-state replacements with live text available/unavailable, equal durable revision, authoritative terminal statuses and fresh watch reconnection. Force actual watch overflow/resync with bounded service settings; assert the marker or pre-stream classified error and successful fresh attachment. Do not model overflow only by manually setting a flag. A HTTP/2 test leaves a healthy watch idle beyond WriteTimeout, then publishes an update to prove the chosen deadline fix.

Privacy fixture inserts only a synthetic opaque provider-state canary through the public state-aware model/codec boundary, then persists/reopens/replays through public APIs. Assert no canary, base64 or content-derived digest enters Go AG-UI output, Dart retained state, widget state or logs. Separate mutation tests inject canaries into SDK raw/custom/state/error payloads to prove defensive client projection. Do not use real private provider state or raw user requests as evidence.

## Evidence matrix

| Requirement | Verification and observable result |
| --- | --- |
| Encoded stream conformance | Both Dart packages consume captured Go frames via exported SDK byte parsing, including UTF-8 split inside a multibyte character, CR/LF splits, every byte boundary of small fixtures, seeded chunking of larger fixtures, multiline/comment frames and malformed/unterminated input. Expected final state is independently asserted. |
| Snapshot/delta and identity | Exact final text after baseline+new delta, repeated equal deltas retained, stable message count, same-name tools remain distinct IDs, empty snapshot clears state. Public-decoder fixtures mix parent/child progress and snapshots with overlapping IDs and ID-less chunks; child attribution never changes parent state, while the opt-in host callback preserves original events. |
| Eino watch continuity | Drop before/after each frame of a snapshot pair, reconnect during paused streaming, reopen store and reconnect. No old-session state leaks, no duplicate durable message, no concatenated replacement text, no falsely complete unavailable live prefix. |
| Terminal delivery | Generic finish/error committed before socket cleanup; EOF is not success. Eino run/tool terminal statuses observed while watch stays open. Absent/success generic finish outcomes mean completed; an encoded interrupt outcome means paused, releases the response and performs no automatic action. Paused, Eino interrupted, failed and completed are distinguishable. Delay admission acknowledgements across watch reconnect and terminal delivery; separately evict the run from a small window and prove truthful outcomeUnknown/explicit reset with no duplicate POST. |
| Bounds | Oversized frame/unterminated data/comment/unknown-field line with limit+1 failure while source remains open, 257th queued event where batching exists, display/text/tool caps, slow listeners, response-body cap, server overflow. Assert exact retained limits, deterministic error and request abort; no retry on deterministic capacity failures. |
| HTTP lifecycle | Loopback server records connection/request-context cancellation before headers and during active SSE; two shared-client requests prove one abort leaves the other running. Browser integration exercises default browser HTTP transport, not just a fake stream. |
| Failures/retries | Initial silent/comment-only watch responses hit the baseline deadline while healthy established idle watches remain open. Fake 401/403 produce distinct states and zero retries; transient watch failures consume at most three attempts. Lost admission response sends one POST only and leaves outcome unknown. Dispose during backoff sends no later GET. |
| Privacy | Synthetic canaries absent from encoded safe replay, serializable view state, rendered/semantic widget tree and captured content-free diagnostics, including malformed/error paths. |
| Accessibility/lifecycle | W4 tests and web examples verify 320px/200% text, keyboard focus, semantic statuses and active-request disposal. |
| Independence/distribution | Generic example resolves without Eino/framework/app-specific dependencies; fresh external consumer resolves exact public Git refs for all packages. No absolute path or local override in final distribution. |

## CI and declared matrix

Use Flutter 3.47.1/bundled Dart 3.13.1 on Ubuntu 24.04 and macOS 15 for analysis/unit/widget tests. Linux additionally builds both web examples, runs Chrome integration tests against the Go server and runs Go 1.26.8 conformance/race tests. Pin CI actions to reviewed commit SHAs when implementing and record tool versions. This is a single-SDK, two-OS initial matrix, not an assertion of all Flutter target support. Android/iOS/Windows native build certification is deferred.

New `tool/verify.sh` must execute, with explicit per-directory working directories:

1. `dart format --output=none --set-exit-if-changed` for package/example/tool Dart sources using bundled Dart.
2. `dart pub get`, `dart analyze`, `dart test` in each pure Dart package.
3. `flutter pub get`, `flutter analyze`, `flutter test` in widget package and each example's applicable tests.
4. `GOWORK=off go mod verify`, `GOWORK=off go test -race ./...` in `conformance/go`; fixture regeneration/verification must produce no committed drift.
5. `flutter build web` in each example and Chrome integration tests against a fixture server allocated an unused port. Implement the runner with bounded readiness/whole-suite deadlines and a trap/finally cleanup that kills only its own server processes and removes only its own temporary SQLite files.
6. `dart run tool/check_boundaries.dart` from root as a file script: inspect per-package `dart pub deps --json` through built-in JSON decoding and scan source import directives for forbidden reverse dependencies, private SDK imports, Go FFI and application-specific packages. This standalone script uses only Dart standard libraries; it requires no missing root pubspec or new YAML parser.
7. `tool/verify_public_consumer.sh` at the distribution checkpoint below.

A script is not a gate until CI actually invokes it and fails on errors. Preserve logs only for tool versions, scenario names, counts and pass/fail categories. Do not persist request contents, headers or raw SDK exceptions in CI output.

## Two example acceptance flows

Generic example: host supplies endpoint and full SDK history, submits two turns, observes text/tool activity and terminal completion, sees an interrupted/disconnected request without automatic re-POST, then disposes the active request. No Eino package may resolve transitively. The host owns canonical request history separately from sanitized widget state using W1's onProtocolEvent callback. Build the second request from actual first-response SDK events, including assistant tool-call ID/arguments and tool-result messages; do not use predetermined second-turn fixture history. Assert that the generic server receives those exact identities and values. No client tool execution or approval flow is needed for this synthetic server-executed-tool scenario.

Eino example: connect to an authorized session; submit one text; observe live replacement; disconnect and reconnect during a paused provider; finish; submit a second text; interrupt it; dispose while watch remains open. Run-count and server-observed history assertions prove one admission per submission. All routes/theme/auth simulation are example-owned injections. No Ensemble/Birbparty/Benchy models are imported.

## Distribution, adoption and rollback

Initial distribution uses pinned public Git package refs. Do not invent a final shared-package SHA during planning. Final implementation acceptance requires actual remotely reachable commits, fresh-consumer resolution and recorded output. Publishing/pushing is a separate implementation-session action; none occurs during planning.

Avoid a self-referential Git pin: first publish/reach a core commit A; dependent widget/Eino package pubspecs refer to core at A; then expose a dependent-packages commit B containing those pubspecs; fresh examples/consumer select core A and widgets/Eino B. Both dependents must name the identical core URL/ref/path so Pub does not resolve conflicting sources. Every direct SDK dependency uses `https://github.com/mattsp1290/ag-ui.git`, ref `691ab5e3846ad5957d1b04a9237167f5496c6232`, path `sdks/community/dart`. The SDK gate is resolved; the old cce5da2 baseline remains nonconformant. Do not mix canonical upstream and fork URLs across package pubspecs. The shared-package A/B publication and fresh-consumer gates remain future work. If core changes after A, select a new core commit and rerun all dependent gates. Local temporary relative overrides must be absent for the final fresh-consumer proof. A later pub.dev release can use hosted versions after namespace/maintainer checks, as separate release work.

Record actual A/B, SDK ref, complete resolved dependency versions, tool versions and conformance result in new `docs/release.md` and the original request's response. Before those exist, response status remains decision/planning, never completion. Existing root LICENSE governs original shared code; if adapting source snippets, preserve required upstream notices after checking source licenses.

`docs/adoption.md` gives sketches only: ag_ui_demo replaces its presentation/service seams while keeping canonical caller history and app tools; its absolute SDK path must be changed in a separate adoption PR. Ensemble must complete the existing backend design request and prove session/run routing/auth before using the Eino adapter. Birbparty has no Eino execution API and remains prospective. Benchy can later request custom renderer hooks; circuit/cache/authorization/diagram work is outside this deliverable. No source repository is edited here.

Rollback before adoption is revert the unreleased commits. After a separately authorized adoption, the host can revert its package pin and local adapter wiring without migrating or deleting Eino history. Breaking changes are acceptable for this new package under confirmed context, but that does not waive a future host's compatibility requirements.
