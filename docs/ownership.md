# Ownership

Matt is the initial maintainer of this repository and the selected AG-UI Dart
SDK fork. Protocol event classes, SSE parsing, request encoding, and generic
JSON Patch behavior stay with the AG-UI SDK owner. This repository owns the
bounded presentation projection, request lifecycle orchestration, Eino watch
pairing, reusable Flutter widgets, examples, and cross-language conformance.

Eino runtime, storage, observation, and HTTP handler corrections belong in
`eino-agent` or `eino-agui`. Consumer route mapping, authorization, credentials,
application state, tool execution, approval, and adoption remain with each host.

Approval/resume UI, rich reasoning, generic state rendering, historical watch
pagination, auth implementation, and real application adoption are outside the
initial packages.
