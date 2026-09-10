# Release evidence

Status: initial Git distribution is ready for consumers.

## Public package commits

- Core commit A: `d51e3a404537b6a2dde09eab9bb792ac3f022e84`
  (`packages/ag_ui_view_state`).
- Dependent-packages commit B:
  `e07e06a89d1a394eb79cea05cbf11f880c685f6d`
  (`packages/ag_ui_widgets` and `packages/eino_session_client`).
- Repository: `https://github.com/mattsp1290/eino-session-client-flutter.git`.

Both dependent pubspecs name the same core A URL, ref, and path. The examples
resolve core at A and the dependent packages at B, without path dependencies or
dependency overrides.

## Immutable dependency pins

- AG-UI Dart: `https://github.com/mattsp1290/ag-ui.git`, path
  `sdks/community/dart`, ref
  `691ab5e3846ad5957d1b04a9237167f5496c6232`.
- Eino agent: `v0.3.4-0.20260908141855-99a87b8cb1ac` (commit
  `99a87b8cb1ac5f11cf39c44f352b7b7849e8d97f`).
- Eino AG-UI: `v0.1.1`.
- AG-UI Go: `v0.0.0-20260624151131-d2049debabd9`.
- HTTP: `1.6.0`.

Flutter 3.47.1 / Dart 3.13.1 archive checksums resolved from the official
release metadata on 2026-09-10:

- Linux x64 `.tar.xz`:
  `a1d8166c0309267cb7dc99f1424eecf08b86946ad3b50723c6f59945964aea45`.
- macOS x64 `.zip`:
  `21e06435c50be9a43ffea8abb549bd7640cd38197e7741dd780f0680afbb64ba`.
- macOS arm64 `.zip`:
  `38c9ffe0af4a71e4600f4fda310f0e895757550926128e28aa57782ea97538fa`.

## Verification

On 2026-09-10, this fresh consumer command ran with a new project and
`PUB_CACHE`, with system/global Git configuration and interactive prompts
disabled:

```sh
CORE_REF=d51e3a404537b6a2dde09eab9bb792ac3f022e84 \
DEPENDENTS_REF=e07e06a89d1a394eb79cea05cbf11f880c685f6d \
tool/verify_public_consumer.sh
```

It resolved `ag_ui_view_state 0.1.0` at A, `ag_ui_widgets 0.1.0` and
`eino_session_client 0.1.0` at B, AG-UI Dart `0.3.0` at the selected SDK
ref, and `http 1.6.0`. Pub resolution, analysis, and dependency graph
inspection exited successfully. Resolution sets `GIT_LFS_SKIP_SMUDGE=1`
because the selected AG-UI Dart package has no LFS assets and the monorepo has
an unrelated dojo fixture whose public LFS endpoint rejects clean CI runners.

The complete local gate passed with Flutter 3.47.1 / Dart 3.13.1 and the Go
module-selected Go 1.26.3 toolchain: package analysis/tests, Go race tests,
fixture regeneration, both web builds, and dependency-boundary checks. The two
Chrome integration suites also passed against the runtime-backed Go fixture
server. They prove server-validated two-turn generic history and Eino
completion, paused live replacement, reconnect, and interruption.

The Linux CI job uses Go 1.26.8 and runs the same gate including Chrome. Record
the first passing GitHub Actions run here after the distribution commit is
pushed. If core changes after A, select another A and repeat the dependent and
consumer gates.
