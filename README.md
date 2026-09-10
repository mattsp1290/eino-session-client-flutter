# Flutter Eino session client

Reusable, bounded AG-UI presentation packages for plain Dart and Flutter hosts.
The repository keeps the two history contracts explicit:

- `ag_ui_view_state` projects public AG-UI events into immutable, size-limited
  text/tool/run state and includes a one-shot caller-owned-history POST adapter.
- `eino_session_client` observes Eino's paired current-state watch snapshots and
  submits only one new user message per admission.
- `ag_ui_widgets` renders accessible transcript, tool activity, paused state,
  and host-controlled input without owning application state or authority.

The generic adapter's `onProtocolEvent` callback is the host boundary for a
canonical transcript. The restricted `AgentViewState` deliberately excludes
tool arguments/results, arbitrary state, metadata, reasoning payloads, raw
events, and raw errors.

## Local verification

Flutter 3.47.1 with bundled Dart 3.13.1 and Go 1.26.8 are the supported initial
toolchain. Run:

```sh
tool/verify.sh
```

The command analyzes and tests all packages, regenerates and compares the real
Go-encoded fixtures, runs Go tests with the race detector, checks dependency
boundaries, and builds both web examples.

## Examples

Start the deterministic fixture host:

```sh
cd conformance/go
GOWORK=off go run ./cmd/fixture-server -addr 127.0.0.1:8080
```

Then run either `examples/generic_ag_ui` or `examples/eino_session` with
Flutter. Endpoints can be supplied through `AG_UI_ENDPOINT`, `EINO_SERVER`, and
`EINO_SESSION` Dart defines. Route mapping, credentials, session authorization,
canonical generic history, and interrupt authority remain host-owned.

See [the integration contract](docs/integration-contract.md) and
[adoption notes](docs/adoption.md) before wiring a consumer.
