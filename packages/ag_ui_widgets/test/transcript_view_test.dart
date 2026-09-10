import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:ag_ui_widgets/ag_ui_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders long text at narrow width and 200 percent scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: TranscriptView(
              omittedOlderMessages: true,
              isStale: true,
              messages: const [
                MessageView(
                  id: 'message',
                  role: ViewMessageRole.assistant,
                  text: 'averyveryveryveryveryverylongword that still wraps safely',
                  liveUnavailable: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Earlier messages are omitted'), findsOneWidget);
    expect(find.text('Showing the last known session state'), findsOneWidget);
    expect(find.text('Live text is unavailable'), findsOneWidget);
  });

  testWidgets('preserves a borrowed scroll controller', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: TranscriptView(
            scrollController: controller,
            messages: const [
              MessageView(
                id: 'message',
                role: ViewMessageRole.user,
                text: 'hello',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(() => controller.addListener(() {}), returnsNormally);
    controller.dispose();
  });
}
