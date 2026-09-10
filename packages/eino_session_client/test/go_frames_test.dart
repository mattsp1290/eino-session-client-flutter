import 'dart:io';

import 'package:ag_ui/ag_ui.dart';
import 'package:eino_session_client/eino_session_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('decodes real Go watch pair with exact exported casing', () async {
    final bytes = await File('../../conformance/fixtures/eino-watch.sse')
        .readAsBytes();
    final client = http.Client();
    final parser = SseClient(
      httpClient: client,
      maxDataCodeUnits: 1048576,
      maxLineCodeUnits: 1048583,
    );
    final events = EventStreamAdapter(maxDataCodeUnits: 1048576).fromSseStream(
      parser.parseStream(
        Stream.fromIterable([
          for (var offset = 0; offset < bytes.length; offset += 7)
            bytes.sublist(
              offset,
              offset + 7 > bytes.length ? bytes.length : offset + 7,
            ),
        ]),
      ),
      skipInvalidEvents: false,
    );
    final projection = WatchProjection(expectedSessionId: 'session-fixture');
    WatchCommit? commit;
    await for (final event in events) {
      commit = projection.add(event) ?? commit;
    }
    await parser.close();
    client.close();

    expect(commit, isNotNull);
    expect(commit!.snapshot.revision, 3);
    expect(commit.snapshot.runs.single.status, EinoRunStatus.completed);
    expect(commit.viewState.tools.map((tool) => tool.id), ['tool-1', 'tool-2']);
  });
}
