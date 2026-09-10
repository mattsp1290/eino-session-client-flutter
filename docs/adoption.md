# Adoption notes

## Generic Flutter host

Create an `AgentViewController`, an owned or borrowed `RequestTransport`, and an
`AgUiPostAdapter`. Attach one fast controller listener to rebuild the host UI.
Keep a separate canonical `List<Message>` and update it from `onProtocolEvent`;
pass that full list in the next `SimpleRunAgentInput`. Never rebuild request
history from `MessageView`, since the presentation projection intentionally
discards tool payloads and other protocol data.

The generic example demonstrates this separation without Eino, Provider,
Riverpod, or application packages.

## Eino session host

Implement `EinoSessionContract` around already-authorized host routes. Build a
fresh request, including fresh credentials, on every method call. Validate any
server-provided route before resolving it. Connect the watch independently from
admission and send only the new text to `EinoSessionAdapter.start`.

Ensemble still needs its backend run/session routing, authentication, admission,
and AG-UI endpoint before adoption. Birbparty currently has no Eino execution
API. Benchy-specific renderers and authority flows require separate work.

After a separately reviewed host adoption, rollback consists of reverting the
host package pin and adapter wiring. No Eino history migration or deletion is
needed.
