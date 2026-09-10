import 'dart:async';

import 'package:flutter/material.dart';

typedef AgentSubmitCallback = Future<void> Function(String text);
typedef AgentInterruptCallback = Future<void> Function();

final class AgentInput extends StatefulWidget {
  const AgentInput({
    required this.onSubmit,
    this.onInterrupt,
    this.enabled = true,
    this.busy = false,
    this.controller,
    this.focusNode,
    this.hintText = 'Message the agent',
    this.submitLabel = 'Send message',
    this.interruptLabel = 'Interrupt run',
    super.key,
  });

  final AgentSubmitCallback onSubmit;
  final AgentInterruptCallback? onInterrupt;
  final bool enabled;
  final bool busy;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final String submitLabel;
  final String interruptLabel;

  @override
  State<AgentInput> createState() => _AgentInputState();
}

final class _AgentInputState extends State<AgentInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late bool _ownsController;
  late bool _ownsFocusNode;
  bool _submitting = false;
  bool _interrupting = false;

  bool get _canSubmit =>
      widget.enabled && !widget.busy && !_submitting && !_interrupting;

  @override
  void initState() {
    super.initState();
    _attachResources();
  }

  @override
  void didUpdateWidget(AgentInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.focusNode != widget.focusNode) {
      _disposeOwnedResources();
      _attachResources();
    }
  }

  void _attachResources() {
    _ownsController = widget.controller == null;
    _ownsFocusNode = widget.focusNode == null;
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  Future<void> _submit() async {
    final text = _controller.text;
    if (!_canSubmit || text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(text);
      if (!mounted) return;
      _controller.clear();
    } on Object {
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _interrupt() async {
    final callback = widget.onInterrupt;
    if (callback == null || _interrupting || _submitting) return;
    setState(() => _interrupting = true);
    try {
      await callback();
    } on Object {
      return;
    } finally {
      if (mounted) setState(() => _interrupting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled && !_submitting,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => unawaited(_submit()),
            decoration: InputDecoration(hintText: widget.hintText),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.busy && widget.onInterrupt != null)
          IconButton(
            tooltip: widget.interruptLabel,
            onPressed: _interrupting ? null : () => unawaited(_interrupt()),
            icon: _interrupting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined),
          )
        else
          IconButton(
            tooltip: widget.submitLabel,
            onPressed: _canSubmit ? () => unawaited(_submit()) : null,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
      ],
    );
  }

  void _disposeOwnedResources() {
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
  }

  @override
  void dispose() {
    _disposeOwnedResources();
    super.dispose();
  }
}
