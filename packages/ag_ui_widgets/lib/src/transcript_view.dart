import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:flutter/material.dart';

final class TranscriptView extends StatefulWidget {
  const TranscriptView({
    required this.messages,
    this.omittedOlderMessages = false,
    this.isStale = false,
    this.emptyLabel = 'No messages yet',
    this.omittedLabel = 'Earlier messages are omitted',
    this.staleLabel = 'Showing the last known session state',
    this.liveUnavailableLabel = 'Live text is unavailable',
    this.scrollController,
    super.key,
  });

  final List<MessageView> messages;
  final bool omittedOlderMessages;
  final bool isStale;
  final String emptyLabel;
  final String omittedLabel;
  final String staleLabel;
  final String liveUnavailableLabel;
  final ScrollController? scrollController;

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

final class _TranscriptViewState extends State<TranscriptView> {
  late ScrollController _controller;
  late bool _ownsController;
  bool _wasNearEnd = true;

  @override
  void initState() {
    super.initState();
    _attachController(widget.scrollController);
  }

  @override
  void didUpdateWidget(TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _detachController();
      _attachController(widget.scrollController);
    }
    if (oldWidget.messages != widget.messages && _wasNearEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _attachController(ScrollController? borrowed) {
    _ownsController = borrowed == null;
    _controller = borrowed ?? ScrollController();
    _controller.addListener(_trackPosition);
  }

  void _detachController() {
    _controller.removeListener(_trackPosition);
    if (_ownsController) _controller.dispose();
  }

  void _trackPosition() {
    if (!_controller.hasClients) return;
    _wasNearEnd =
        _controller.position.maxScrollExtent - _controller.offset <= 80;
  }

  @override
  Widget build(BuildContext context) {
    final notices = <Widget>[
      if (widget.omittedOlderMessages)
        _Notice(label: widget.omittedLabel, icon: Icons.history),
      if (widget.isStale)
        _Notice(label: widget.staleLabel, icon: Icons.cloud_off_outlined),
    ];
    if (widget.messages.isEmpty && notices.isEmpty) {
      return Center(child: Text(widget.emptyLabel));
    }
    return ListView.builder(
      controller: _controller,
      itemCount: notices.length + widget.messages.length,
      itemBuilder: (context, index) {
        if (index < notices.length) return notices[index];
        final message = widget.messages[index - notices.length];
        return _MessageRow(
          key: ValueKey<String>('message-${message.id}'),
          message: message,
          liveUnavailableLabel: widget.liveUnavailableLabel,
        );
      },
    );
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }
}

final class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.liveUnavailableLabel,
    super.key,
  });

  final MessageView message;
  final String liveUnavailableLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ViewMessageRole.user;
    final roleLabel = isUser ? 'You' : 'Assistant';
    return Semantics(
      label: '$roleLabel message',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(roleLabel, style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(message.text),
                if (message.liveUnavailable) ...[
                  const SizedBox(height: 6),
                  Text(
                    liveUnavailableLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Notice extends StatelessWidget {
  const _Notice({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  );
}
