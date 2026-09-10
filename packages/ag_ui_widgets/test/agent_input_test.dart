import 'dart:async';

import 'package:ag_ui_widgets/ag_ui_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('prevents duplicate sends and clears only after success', (
    tester,
  ) async {
    final accepted = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(
            onSubmit: (_) {
              calls += 1;
              return accepted.future;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send), warnIfMissed: false);
    expect(calls, 1);
    expect(find.text('hello'), findsOneWidget);
    accepted.complete();
    await tester.pump();
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('retains input after rejected submission', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(onSubmit: (_) async => throw StateError('rejected')),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'keep me');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(find.text('keep me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount preserves borrowed resources during pending submit', (
    tester,
  ) async {
    final pending = Completer<void>();
    final controller = TextEditingController(text: 'text');
    final focusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(
            controller: controller,
            focusNode: focusNode,
            onSubmit: (_) => pending.future,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(() => controller.text = 'still owned', returnsNormally);
    expect(() => focusNode.requestFocus(), returnsNormally);
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('keyboard action submits once and blank input does not submit', (
    tester,
  ) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(onSubmit: (text) async => submitted.add(text)),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'keyboard');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(submitted, ['keyboard']);

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(submitted, ['keyboard']);
  });

  testWidgets('busy interrupt failures are contained and action stays usable', (
    tester,
  ) async {
    var interrupts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentInput(
            busy: true,
            onSubmit: (_) async {},
            onInterrupt: () async {
              interrupts += 1;
              throw StateError('host rejected interrupt');
            },
          ),
        ),
      ),
    );
    expect(find.byTooltip('Interrupt run'), findsOneWidget);
    await tester.tap(find.byTooltip('Interrupt run'));
    await tester.pump();
    expect(interrupts, 1);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Interrupt run'), findsOneWidget);
  });
}
