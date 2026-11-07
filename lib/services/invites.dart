import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/common.dart';
import 'api.dart';
import 'config_store.dart';

/// Opens the system share sheet with the user's invite code. Whoever signs up
/// with it becomes their friend straight away.
Future<void> shareInvite(BuildContext context) async {
  try {
    final (code, _) = await Api.myInvite();
    final cfg = ConfigStore.current;
    final message = cfg.inviteMessage.isEmpty
        ? 'Talk to me on VoxLink 🎙️ Sign up with my invite code $code and we\'ll be friends right away.'
        : cfg.inviteMessage.replaceAll('{code}', code);
    final text = cfg.inviteLink.isEmpty ? message : '$message\n${cfg.inviteLink}';
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: text,
      subject: 'Join me on VoxLink',
      // iPad needs an anchor for the share popover.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message, error: true);
  }
}
