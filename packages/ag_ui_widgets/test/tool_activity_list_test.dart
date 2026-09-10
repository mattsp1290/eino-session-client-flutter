import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:ag_ui_widgets/ag_ui_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('same-name tools have stable keys and text statuses', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToolActivityList(
            runPhase: RunPhase.paused,
            tools: [
              ToolActivityView(
                id: 'one',
                name: 'lookup',
                phase: ToolActivityPhase.awaitingResult,
              ),
              ToolActivityView(
                id: 'two',
                name: 'lookup',
                phase: ToolActivityPhase.completed,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('tool-one')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tool-two')), findsOneWidget);
    expect(find.text('Waiting for host action'), findsOneWidget);
    expect(find.text('Awaiting result'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
