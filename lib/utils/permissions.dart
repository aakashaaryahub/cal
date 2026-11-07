import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Asks for the microphone, explaining why (or pointing to Settings) if needed.
Future<bool> ensureMicPermission(BuildContext context) async {
  var status = await Permission.microphone.request();
  if (status.isGranted) return true;
  if (!context.mounted) return false;
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Microphone needed'),
      content: const Text('VoxLink needs your microphone so the other person can hear you.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(status.isPermanentlyDenied ? 'Open settings' : 'Allow'),
        ),
      ],
    ),
  );
  if (open != true) return false;
  if (status.isPermanentlyDenied) {
    await openAppSettings();
    return false;
  }
  status = await Permission.microphone.request();
  return status.isGranted;
}
