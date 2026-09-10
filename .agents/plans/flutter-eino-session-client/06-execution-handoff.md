# Execution handoff

Planning only. No implementation has occurred. Read [00](00-overview.md) and preserve its user-confirmed application context. All implementation paths and symbol names in W1–W5 are proposed and anchored to existing root `.`. Existing editable files are `README.md` and `.gitignore`; preserve `LICENSE` and unrelated external checkout changes.

## Dependency order

| Package | Prerequisites | Bounded result | Verification |
| --- | --- | --- | --- |
| W1 — Contract/package foundation | Confirmed context/ownership plus corrected public SDK pin | Three package manifests/barrels and host-injected interfaces; exact dependency graph | Per-package pub resolution/analysis; public API compile checks; standalone Go module resolution, no local replace |
| W2 — Generic projection | W1 | Bounded safe state keyed by message/tool IDs | Core reducer, privacy, bounds and controller tests in [02](02-generic-projection.md) |
| W3 — Distinct adapters | W1, W2 | Generic full-history POST and optional Eino fresh-watch/new-message control | HTTP cancellation/failure tests and exact watch tests in [03](03-transport-adapters.md) |
| W4 — Widgets | W1, W2 | Themeable text/tool/input components | Widget/accessibility/focus/disposal tests in [04](04-flutter-widgets.md) |
| W5 — Conformance/delivery | W1–W4 complete | Go fixtures/server, two plain examples, executable CI, usable public pins and honest adoption record | Full [05](05-conformance-and-delivery.md) evidence matrix and fresh consumer |

Start the Go conformance harness portion of W5 immediately after W1 as an integration feedback step, then complete W2/W3 against its frames. W4 can proceed alongside W3 after W2 public state stabilizes; both depend on the same API and must coordinate changes. Final examples/CI/public-consumer gates run after all packages. Do not parallelize changes to shared pubspecs or public state definitions without coordination. Sequential implementation remains valid; this plan authorizes no autonomous implementation.

## First implementation action and stop/go gates

SDK dependency readiness is verified at `https://github.com/mattsp1290/ag-ui.git`, commit `691ab5e3846ad5957d1b04a9237167f5496c6232`, path `sdks/community/dart`. PR #46's final branch head is publicly consumable even while the PR remains open. Preserve that immutable tuple across packages; do not wait for a merge or create an implementation workaround.

First implementation action: open [01-contract-and-packages.md](01-contract-and-packages.md) and establish the three package skeletons with the selected SDK APIs. Validate the complete shared dependency graph before implementing behavior. Do not use moving SDK/Eino checkout HEADs as evidence for the selected pins.

The mapped SDK request is resolved according to its latest owner response and [fresh consumer evidence](sdk-pin-verification.json). If another dependency fails public resolution or lacks a required API, stop the affected work package, capture a content-free reproduction and file an owner-specific request. Matt owns SDK corrections; Eino maintainers own transport/runtime changes. Repinning requires renewed conformance; returning to the original unbounded parser reopens the SDK gate. Do not weaken cancellation/reconnect/privacy gates or copy protocol code.

Every behavior-changing package uses feature_flags=not-applicable and may change this new package's API/configuration freely. There is no existing package data to migrate. Initial examples store no secrets or client transcript database. Publishing, host adoption and external writes are separate authorized implementation/release steps with concrete artifact/consumer evidence.

## Integration and regression gates

- Public SDK types/codec/parser used throughout; no private imports, event forks, JSON-patch copy, Go embedding or application dependencies.
- Full-history generic request and single-new-message Eino request are separately proven by server assertions, not inferred from UI screenshots.
- Real encoded fixtures plus live HTTP/Chrome tests prove snapshot pairing, stable IDs, terminal delivery, fresh-watch recovery, initial-baseline timeout, independent watch/control identities, truthful outcomeUnknown for evicted terminals, cancellation, bounded buffers and no duplicate admission.
- Widget gates prove narrow/large text, focus/semantics, inherited theme and disposal with an active request.
- Opaque synthetic canaries remain absent from encoded replay, retained/rendered state and diagnostics.
- CI runs the complete new `tool/verify.sh` on the declared matrix, with correct working directories and bounded server cleanup. Required checks must not be skipped because a mock test passed.
- Fresh external consumer resolves actual public A/B package Git refs without workspace, overrides or absolute path dependencies. Record exact pins in release documentation and the request response before claiming completion.

## Definition of done

All W1–W5 verification passes. Both examples run with their host-injected routes and history ownership contracts. The generic example's dependency graph has no Eino/Provider/Riverpod or host-specific package. The Eino watch window is authoritative and bounded, with truthful unavailable/stale/terminal states. Cancellation releases only its own operations. There are no live provider credentials or prompts in fixtures. Distribution pins resolve publicly, and the response distinguishes repository ownership, implementation completion and readiness of each future host API. No host integration is claimed completed by shared-package work.

## Deferred work

Approval/ask-user routing, custom renderer/Benchy circuit hooks, rich reasoning presentation, generic state patch rendering, pagination, historical event replay, execution resume, auth implementation, additional SDK versions/native platform build certification, pub.dev publication and real host adoption remain separate requests. Reuse Ensemble's existing backend design request. Birbparty does not gain agent features as part of this work.
