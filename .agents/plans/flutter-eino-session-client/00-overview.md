# Flutter Eino session client

Status: Ready — SDK blocker resolved at verified public PR #46 head `691ab5e3846ad5957d1b04a9237167f5496c6232`. Two independent revision reviews and one fresh adversarial review completed; accepted findings are incorporated. Operating context and maintainer remain confirmed. Shared-package implementation has not occurred.

## Application context

```json
{
  "application_context": {
    "has_active_users": false,
    "backward_compatibility_required": false,
    "feature_flags": "not-applicable",
    "confirmation_digest": "f1af96e08fc171607dca519f35fb94b9bc70b3159edeca4a487229f3e859ee84",
    "confirmed_at": "2026-09-08T15:31:22Z"
  }
}
```

User confirmation: “No active users, ignore backwards compatibility.” No legacy API, storage, configuration or workflow migration is required. Feature flags are not applicable in every work package. Consumer integrations are separate future changes with their own operating context.

## Outcome and scope

Create reusable Dart event-to-view-state and Flutter text/tool/input components in this existing repository, with a separate optional Eino session adapter. Change type: new library and examples. Affected areas: package boundaries, public Dart API, HTTP lifecycle, projection, widgets, Go conformance harness, CI and adoption documentation.

Success means both plain Flutter examples build and run, the generic example sends a full caller-owned transcript, and the Eino example submits only new user text and displays a durable server-owned transcript after disconnect/reconnect. Real Go-encoded SSE must pass Dart decoding, projection, cancellation, bounded-memory and privacy tests. Widgets must pass narrow-width, large-text, focus, semantics and disposal tests. A fresh consumer must resolve public immutable package pins without absolute path dependencies before adoption is claimed.

Exclude Go embedding/FFI, a second protocol or copied event types/parsers, generic JSON-patch implementation, auth/OAuth/secret persistence, application state-management frameworks, approval/ask-user routing, delegated tasks, web search, Python REPL, background jobs, a dashboard/design system and actual host adoption. Approval widgets are deferred; no button may infer authority or settle a tool without a host callback. No Ensemble backend work or Birbparty agent features are authorized.

## Repository facts and ownership

- This repository starts at `f8da209` with only `README.md`, `LICENSE`, and `.gitignore`. No local contributor guide, AGENTS.md, source, tests, pubspec or CI exists. The worktree was clean at research. `.gitignore` ignores all `*.lock`, which must be narrowed to permit reproducibility locks.
- The named `eino-agent-flutter` sibling is also an empty scaffold. Use the invocation repository `eino-session-client-flutter`; do not create or move another repository. Initial maintainer: Matt, explicitly confirmed by the user. Matt also confirmed ownership of the AG-UI Dart SDK.
- The AG-UI SDK library exposes Dart event types, request encoding, SSE parsing and client state tracking without a Flutter dependency or exported widgets. The selected pin now includes Flutter widgets and projection in `sdks/community/dart/example/lib/`, which are application example code, not a reusable exported library or an Eino adapter. Inspect those as current source patterns while keeping protocol/JSON-patch fixes with their existing owner. `ag_ui_demo` has concrete text/input/event reconciliation and Ensemble has a routed stream client and event viewer. These justify the shared presentation owner. SDK protocol/JSON-patch fixes remain upstream; runtime and Go emission remain in eino-agent/eino-agui.
- Ensemble's inspected UI uses `AgUiStreamClient.streamRun(beanId, runAttemptId)` and pins older Dart commit `0278d5a23ad2e2eb5e95a4e1fb133cf0eb143d58`. Its design documentation describes no seek/resume contract. This is not evidence of a ready server-owned history API. Existing host design work remains a separate adoption prerequisite.
- `ag_ui_demo` at `1d1fa327d70d416cac909288497a6a07f94b313d` uses `SimpleRunAgentInput` and `AgUiClient.runAgent` with caller-owned history. Its absolute SDK path and unrelated dirty iOS/macOS files must remain untouched here.
- Birbparty at `0a037dc0d696cf6ea09e006d9c7145b0ab9f8291` is an account API plus Flutter UI, a prospective agent consumer only. Benchy's supplemental request is evidence for the newer watch boundary, not authorization for diagram features here.
- Eino v0.3.3 has `transport.SSEHandler` and durable-history replay, but no `SessionWatchHandler`. The selected newer immutable pin in [01](01-contract-and-packages.md) exposes bounded current-state observation and correct HTTP/2 write-deadline cleanup. Public proxy download and checksum resolution succeeded during research. The sibling checkout moved during research; use the selected immutable source, not its moving HEAD.

## Target architecture and decisions

```text
Host routes / auth / IDs / actions / theme
  ├─ generic caller-owned POST adapter ─┐
  └─ optional Eino watch adapter ──────┤
                     SDK decoding → bounded Dart projection → Flutter widgets
```

Proposed package dependency graph: `ag_ui_widgets → ag_ui_view_state → ag_ui`; `eino_session_client → ag_ui_view_state`. The core remains pure Dart. Widgets never depend on Eino, Riverpod, Provider, Ensemble beans/run-attempts, Birbparty authorization or application branding. Host-owned request/action data is separate from allowlisted presentation state. The selected SDK's child-agent attribution is filtered before parent projection, and its run-finish interrupt outcome is shown as paused without introducing approval/resume routing.

The generic adapter uses public SDK `Encoder`, `SseClient.parseStream`, and `EventStreamAdapter`. It uses an injected abortable HTTP transport instead of the high-level SDK client's documented logical-only pending-send cancellation. This is transport orchestration, not a parser or wire-format fork.

The Eino adapter selects current snapshot observation, not historical event replay. Reconnect opens a fresh GET and replaces state. It neither emits nor interprets `Last-Event-ID` or invented cursor headers. Eino watch sends paired message/state snapshots including already-composed transient text, so the client must not append that text again. Generic snapshots followed by deltas retain their own semantics.

## Sources and portable resolution

Set `ENSEMBLE_ROOT`, `AG_UI_DEMO_ROOT`, `BIRBPARTY_ROOT`, `AG_UI_ROOT`, and `EINO_AGENT_ROOT` to local checkouts of the named repositories. Inspect pinned content with `git show <commit>:<path>` even if a checkout is dirty or ahead. For Eino, alternatively resolve the module directory from `GOWORK=off go mod download -json github.com/mattsp1290/eino-agent@v0.3.4-0.20260908141855-99a87b8cb1ac` and use its `Dir` field.

Authoritative source paths: `$AG_UI_ROOT/sdks/community/dart/lib/ag_ui.dart`, `lib/src/client/client.dart`, `lib/src/encoder/client_codec.dart`, `lib/src/sse/sse_client.dart`; `$EINO_AGENT_ROOT/transport/watch.go`, `agui/watch.go`, `session/observation.go`, `watch/types.go`, `docs/consumer-guide.md`, `examples/minimal-server/`, `testdata/external-consumer/session_watch_fixture_test.go`; `$ENSEMBLE_ROOT/apps/ui/lib/features/agui/agui_stream_client.dart`, `apps/ui/docs/architecture.md`, `apps/ui/pubspec.yaml`; `$AG_UI_DEMO_ROOT/lib/services/ag_ui_service.dart`, `lib/pages/agui_event_handling.dart`, `lib/widgets/`, `pubspec.yaml`; `$BIRBPARTY_ROOT/README.md`, `api/README.md`, `ui/pubspec.yaml`. Short source paths in the AG-UI clause are relative to `$AG_UI_ROOT/sdks/community/dart`; short paths in other clauses are relative to their named checkout root. External planning records include the ownership response and the preserved SDK correction request/owner response. This revision updates only the local plan and shared-client ownership response. No external source code is changed.

## External request and response map

Resolve `$HOME` through the environment. Canonical documents are local planning records, not package pins.

| Document | Owner and consumers | Local effect and unblock evidence |
| --- | --- | --- |
| `$HOME/.agents/projects/eino-flutter/requests/2026-09-07-create-flutter-eino-session-client.md` | Matt decides initial maintainer; concrete source consumers Ensemble and ag_ui_demo; prospective Birbparty | Governs W1–W5. Assignment is confirmed. Package completion/adoption needs public package pin plus Go/Dart evidence and separately ready host API. |
| `$HOME/.agents/projects/eino-flutter/requests/2026-09-07-benchy-session-and-diagram-host-contract.md` | Matt/shared package owner; intended Benchy | Non-blocking supplemental evidence. Fresh watch semantics align; diagram custom slots and Benchy schemas remain deferred. Do not claim this supplemental request fulfilled. |
| `$HOME/.agents/projects/ensemble/requests/2026-06-27-eino-agui-adapter-design.md` | Ensemble backend maintainers; Ensemble UI | Non-blocking for this library, blocking for Ensemble adoption. Requires a working host run/session mapping, auth, admission and AG-UI endpoint with integration evidence. Reuse this request, do not duplicate it. |
| `$HOME/.agents/projects/ag-ui/requests/2026-09-08-bounded-dart-sse-byte-parser.md` and existing `$HOME/.agents/projects/ag-ui/responses/2026-09-08-bounded-dart-sse-byte-parser.md` | Matt, confirmed SDK maintainer; shared client and existing API consumers Ensemble/ag_ui_demo | Resolved for W1/W3/W5 by public fork commit `691ab5e3846ad5957d1b04a9237167f5496c6232`. Owner acceptance/completion are recorded in the response; September 10 fresh anonymous resolution, exact lock/cache checks, standalone analysis and public byte probe passed. The historical request remains preserved; the latest owner response supersedes its open-state wording and older implementation pins. |
| `$HOME/.agents/projects/eino-flutter/responses/2026-09-07-create-flutter-eino-session-client.md` (new planning response) | This planner records decision for Matt and requesting Ensemble planning | Records existing repository, maintainer decision, layout, exact dependency pins and future completion gates. No implementation or published shared package is claimed. |

Resolved upstream prerequisite: original SDK ref `cce5da216ed936902e703ba4317d206832ff8eee` buffered incomplete lines before limits. Matt's PR [#46](https://github.com/mattsp1290/ag-ui/pull/46) supplies the corrected parser at `691ab5e3846ad5957d1b04a9237167f5496c6232`, publicly resolved from `https://github.com/mattsp1290/ag-ui.git`, package path `sdks/community/dart`. Pin this exact fork URL/SHA/path consistently; do not substitute the canonical upstream URL or a moving branch. Local branch tip, PR head and the latest owner response agree. PR #46 remains open and stacked; a merge or pub.dev release is not required for this authorized immutable Git dependency.

[SDK pin verification evidence](sdk-pin-verification.json) records the September 10 fresh-cache consumer checks. The SDK's [Dart CI run](https://github.com/mattsp1290/ag-ui/actions/runs/34364875071) passed on this SHA. Unrelated npm preview-publishing jobs failed; no all-PR-checks-green or npm publication claim is made. Eino dependency availability remains independently verified. This closes only the SDK prerequisite; W1–W5 and shared-package publication are still future implementation.

## Risks, assumptions and decisions

No unresolved blocking user decision or external dependency remains. Matt confirmed shared-repository and SDK maintainership and explicitly selected PR #46's final branch commit. Repinning away from the verified correction requires repeating SDK conformance and public resolution; returning to the old nonconformant SDK reopens this gate.

Non-blocking choices: proposed package names are local defaults; initial distribution uses public pinned Git rather than requiring a pub.dev namespace. The initial supported SDK is Flutter 3.47.1 / bundled Dart 3.13.1 on Linux CI with Chrome plus macOS CI. Expanding the version/platform matrix is deferred. This version is installed locally; re-resolve the official Flutter SDK archive in implementation and record the downloaded artifact hash. See [Flutter SDK archive](https://docs.flutter.dev/install/archive) for version provenance.

Primary risks: pairing watch snapshots across a dropped connection, late callbacks crossing sessions, pending-send aborts, paused subscriber buffers, unknown/evicted admission outcome, initial-baseline silence, public Git transitive dependency resolution and JavaScript integer precision. Concrete policies are in work files. There is no storage migration. Rollback is reverting unreleased package changes or a future consumer reverting its package pin; do not modify external host data or delete its state.

## Document map

1. [01 — Contract and packages](01-contract-and-packages.md): immutable dependencies, public API seams and package setup (W1).
2. [02 — Generic projection](02-generic-projection.md): bounded safe state and event reconciliation (W2).
3. [03 — Transport adapters](03-transport-adapters.md): two history contracts, lifecycle, reconnection and ownership (W3).
4. [04 — Flutter widgets](04-flutter-widgets.md): themeable presentation and accessible interaction (W4).
5. [05 — Conformance and delivery](05-conformance-and-delivery.md): Go fixture server, examples, CI and usable distribution (W5).
6. [06 — Execution handoff](06-execution-handoff.md): ordered gates, verification and final definition of done.

The supporting [SDK verification record](sdk-pin-verification.json) is planning evidence, not an implementation artifact.
