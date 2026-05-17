import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Show a modal dialog that lets the user enter a page number directly
/// and jump to it. Returns the validated page number, or `null` if the
/// user cancelled. The page is bounded to `[1, totalPages]`.
Future<int?> showJumpToPageDialog(
  BuildContext context, {
  required int currentPage,
  required int totalPages,
}) {
  return showDialog<int?>(
    context: context,
    builder: (ctx) => _JumpToPageDialog(
      currentPage: currentPage,
      totalPages: totalPages,
    ),
  );
}

class _JumpToPageDialog extends StatefulWidget {
  const _JumpToPageDialog({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  @override
  State<_JumpToPageDialog> createState() => _JumpToPageDialogState();
}

class _JumpToPageDialogState extends State<_JumpToPageDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(int.parse(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to page'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Page (1\u2013${widget.totalPages})',
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null) return 'Enter a page number';
            if (n < 1 || n > widget.totalPages) {
              return 'Out of range (1\u2013${widget.totalPages})';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}
