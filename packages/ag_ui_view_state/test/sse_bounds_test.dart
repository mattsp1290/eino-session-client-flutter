import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  for (final line in [
    'data: 1234567890',
    ':123456789012345',
    'unknown: 1234567',
  ]) {
    test(
      'line limit aborts an open source for ${line.split(':').first}',
      () async {
        final cancelled = Completer<void>();
        final source = StreamController<List<int>>(
          onCancel: () {
            if (!cancelled.isCompleted) cancelled.complete();
          },
        );
        final httpClient = http.Client();
        final parser = SseClient(
          httpClient: httpClient,
          maxDataCodeUnits: 8,
          maxLineCodeUnits: 15,
        );
        final result = parser.parseStream(source.stream).drain<void>();
        source.add(utf8.encode(line));

        await expectLater(
          result.timeout(const Duration(seconds: 2)),
          throwsA(isA<FormatException>()),
        );
        await cancelled.future.timeout(const Duration(seconds: 2));
        await parser.close();
        httpClient.close();
        await source.close();
      },
    );
  }
}
