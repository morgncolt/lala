// lib/widgets/consent.dart
import 'package:flutter/material.dart';

Future<bool> confirmOnChain(BuildContext ctx, {required String title, required String summary}) async {
  return await showDialog<bool>(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(summary),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm & Sign')),
      ],
    ),
  ) ?? false;
}