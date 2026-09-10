# Release evidence

Status: implementation is local; public package commits A/B are not recorded
yet. Do not claim external consumer readiness until the publication procedure
below succeeds.

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

## Publication checkpoint

Publish a core commit A whose `packages/ag_ui_view_state` is reachable. Change
both dependent pubspecs to the identical repository URL/ref/path for core A,
then publish dependent commit B. Remove every relative override from the final
consumer proof and run:

```sh
CORE_REF=<A> DEPENDENTS_REF=<B> tool/verify_public_consumer.sh
```

Record A, B, the resolved lock versions, CI run, and fresh-consumer result here
only after they exist. If core changes after A, select another A and repeat the
dependent and consumer gates.
