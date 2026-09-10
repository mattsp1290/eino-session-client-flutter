import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:flutter/material.dart';

final class ToolActivityList extends StatelessWidget {
  const ToolActivityList({
    required this.tools,
    this.runPhase = RunPhase.idle,
    super.key,
  });

  final List<ToolActivityView> tools;
  final RunPhase runPhase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (runPhase == RunPhase.paused)
          Semantics(
            liveRegion: true,
            label: 'Waiting for host action',
            child: ListTile(
              leading: Icon(Icons.pause_circle_outline),
              title: Text('Waiting for host action'),
            ),
          ),
        for (final tool in tools)
          _ToolRow(key: ValueKey<String>('tool-${tool.id}'), tool: tool),
      ],
    );
  }
}

final class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool, super.key});

  final ToolActivityView tool;

  @override
  Widget build(BuildContext context) {
    final status = _status(tool.phase);
    return Semantics(
      label: '${tool.name}: $status',
      child: ListTile(
        leading: Icon(_icon(tool.phase)),
        title: Text(tool.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(status),
      ),
    );
  }

  String _status(ToolActivityPhase phase) => switch (phase) {
    ToolActivityPhase.receivingArguments => 'Receiving arguments',
    ToolActivityPhase.awaitingResult => 'Awaiting result',
    ToolActivityPhase.resultObserved => 'Result observed',
    ToolActivityPhase.running => 'Running',
    ToolActivityPhase.completed => 'Completed',
    ToolActivityPhase.failed => 'Failed',
    ToolActivityPhase.interrupted => 'Interrupted',
    ToolActivityPhase.unresolved => 'Unresolved',
  };

  IconData _icon(ToolActivityPhase phase) => switch (phase) {
    ToolActivityPhase.receivingArguments ||
    ToolActivityPhase.awaitingResult ||
    ToolActivityPhase.running => Icons.pending_outlined,
    ToolActivityPhase.resultObserved ||
    ToolActivityPhase.completed => Icons.check_circle_outline,
    ToolActivityPhase.failed => Icons.error_outline,
    ToolActivityPhase.interrupted => Icons.cancel_outlined,
    ToolActivityPhase.unresolved => Icons.help_outline,
  };
}
