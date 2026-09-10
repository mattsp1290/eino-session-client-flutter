import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:ag_ui_widgets/ag_ui_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'messages, notices, tools, and paused state have text semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: TranscriptView(
                    isStale: true,
                    messages: [
                      MessageView(
                        id: 'assistant',
                        role: ViewMessageRole.assistant,
                        text: 'Visible response',
                        liveUnavailable: true,
                      ),
                    ],
                  ),
                ),
                ToolActivityList(
                  runPhase: RunPhase.paused,
                  tools: [
                    ToolActivityView(
                      id: 'tool',
                      name: 'lookup',
                      phase: ToolActivityPhase.interrupted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Assistant message')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Showing the last known session state')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('lookup: Interrupted')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Waiting for host action')),
        findsOneWidget,
      );
      expect(find.text('Completed'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('disabled input exposes an unavailable send action', (
    tester,
  ) async {
    final inputFocus = FocusNode(debugLabel: 'input');
    addTearDown(inputFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(
            focusNode: inputFocus,
            enabled: false,
            onSubmit: (_) async {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('Send message'), findsOneWidget);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('Tab moves focus from the editor to the send action', (
    tester,
  ) async {
    final inputFocus = FocusNode(debugLabel: 'input');
    addTearDown(inputFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(focusNode: inputFocus, onSubmit: (_) async {}),
        ),
      ),
    );
    inputFocus.requestFocus();
    await tester.pump();
    expect(inputFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(inputFocus.hasFocus, isFalse);
    final primary = FocusManager.instance.primaryFocus;
    expect(primary, isNotNull);
    expect(primary, isNot(same(inputFocus)));
    expect(
      primary!.context!.findAncestorWidgetOfExactType<IconButton>(),
      isNotNull,
    );
  });
}
