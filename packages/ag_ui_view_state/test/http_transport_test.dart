import 'dart:async';
import 'dart:io';

import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'aborting one request preserves another request on a borrowed client',
    () async {
      final slowArrived = Completer<void>();
      final releaseSlow = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        if (request.uri.path == '/slow') {
          slowArrived.complete();
          await releaseSlow.future;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write('data: {}\n\n');
          await request.response.close();
        } else {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write('data: {}\n\n');
          await request.response.close();
        }
      });
      final client = http.Client();
      final transport = HttpRequestTransport(client);
      final base = Uri.parse('http://${server.address.host}:${server.port}');
      final slow = transport.open(
        RequestSpec(method: 'GET', uri: base.resolve('/slow')),
      );
      await slowArrived.future;
      final fast = transport.open(
        RequestSpec(method: 'GET', uri: base.resolve('/fast')),
      );
      final fastResponse = await fast.response;
      expect(fastResponse.statusCode, 200);

      await slow.abort();
      releaseSlow.complete();
      await expectLater(
        slow.response.timeout(const Duration(seconds: 2)),
        throwsA(anything),
      );
      final secondFast = transport.open(
        RequestSpec(method: 'GET', uri: base.resolve('/fast')),
      );
      expect((await secondFast.response).statusCode, 200);

      await transport.dispose();
      client.close();
      await server.close(force: true);
      await serving.cancel();
    },
  );
}
