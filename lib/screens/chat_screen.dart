import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_profile.dart';
import '../services/api.dart';
import '../services/social_store.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';
import '../widgets/social_widgets.dart';
import 'outgoing_call_screen.dart';

class ChatScreen extends StatefulWidget {
  final Peer peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _pollEvery = Duration(milliseconds: 2500);

  final _input = TextEditingController();
  final _messages = <ChatMessage>[];
  final _pending = <String>[];
  Timer? _poll;
  bool _loading = true;
  bool _locked = false;
  int _seenUpTo = 0;
  int _firstLoadMaxId = 0;

  int get _lastId => _messages.isEmpty ? 0 : _messages.last.id;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _fetch(initial: true);
    _poll = Timer.periodic(_pollEvery, (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    SocialStore.refresh();
    super.dispose();
  }

  Future<void> _fetch({bool initial = false}) async {
    try {
      final (msgs, seen) = await Api.messages(widget.peer.id, after: _lastId);
      if (!mounted) return;
      setState(() {
        final known = _messages.map((m) => m.id).toSet();
        _messages.addAll(msgs.where((m) => !known.contains(m.id)));
        _seenUpTo = seen;
        if (initial) _firstLoadMaxId = _lastId;
        _loading = false;
        _locked = false;
      });
      if (!initial && msgs.any((m) => !m.fromMe)) HapticFeedback.selectionClick();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _locked = e.code == 'NOT_FRIENDS';
      });
      if (_locked) _poll?.cancel();
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _locked) return;
    _input.clear();
    HapticFeedback.lightImpact();
    setState(() => _pending.add(text));
    try {
      final msg = await Api.sendMessage(widget.peer.id, text);
      if (!mounted) return;
      setState(() {
        _pending.remove(text);
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(text));
      _input.text = text;
      showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    // Newest at the bottom: the list is reversed, so build newest-first.
    final items = <_Item>[
      for (final t in _pending.reversed) _Item.pending(t),
      for (final m in _messages.reversed) _Item.message(m),
    ];
    final lastMine = _messages.lastWhere((m) => m.fromMe, orElse: () => _dummy).id;

    return Scaffold(
      body: AuroraBackground(
        intensity: 0.12,
        child: SafeArea(
          child: Column(
            children: [
              _header(peer),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
                    : items.isEmpty
                        ? _emptyState(peer)
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];
                              final m = item.message;
                              final bubble = _Bubble(
                                text: item.text,
                                fromMe: m?.fromMe ?? true,
                                time: m?.createdAt,
                                pending: m == null,
                                seen: m != null && m.id == lastMine && _seenUpTo >= m.id,
                              );
                              // Only animate messages that arrive while the chat is open.
                              final fresh = m == null || m.id > _firstLoadMaxId;
                              return fresh
                                  ? bubble
                                      .animate()
                                      .fadeIn(duration: 250.ms)
                                      .slideY(begin: 0.3, curve: Curves.easeOutCubic)
                                      .scaleXY(begin: 0.9, alignment: m?.fromMe == false ? Alignment.bottomLeft : Alignment.bottomRight)
                                  : bubble;
                            },
                          ),
              ),
              _locked ? _lockedBanner(peer) : _composer(),
            ],
          ),
        ),
      ),
    );
  }

  static final _dummy = ChatMessage.fromJson(const {'id': -1, 'text': '', 'fromMe': true});

  Widget _header(Peer peer) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Expanded(
            child: Pressable(
              onTap: () => showUserSheet(context, peer),
              child: Row(
                children: [
                  InitialsAvatar(name: peer.name, size: 42, countryCode: peer.countryCode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(peer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(
                          peer.location.isEmpty ? 'Tap for profile' : peer.location,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Pressable(
            onTap: _locked ? null : () => Navigator.of(context).push(fadeRoute(OutgoingCallScreen(peer: peer))),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: _locked ? null : AppColors.brandGradient,
                color: _locked ? AppColors.surfaceHigh : null,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(Peer peer) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👋', style: TextStyle(fontSize: 56))
              .animate(onPlay: (c) => c.repeat())
              .rotate(begin: -0.05, end: 0.08, duration: 300.ms)
              .then()
              .rotate(begin: 0.08, end: -0.05, duration: 300.ms)
              .then(delay: 1200.ms),
          const SizedBox(height: 12),
          Text('Say hi to ${peer.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('You\'re friends now. Start the conversation!', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _lockedBanner(Peer peer) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Text(
        '🔒  You and ${peer.name} no longer follow each other, so chat is closed.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _composer() {
    final canSend = _input.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message',
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(26)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: AppColors.stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: AppColors.pink, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedScale(
            scale: canSend ? 1 : 0.8,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: canSend ? 1 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Pressable(
                onTap: canSend ? _send : null,
                pressedScale: 0.85,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final ChatMessage? message;
  final String text;
  _Item.message(ChatMessage m)
      : message = m,
        text = m.text;
  _Item.pending(this.text) : message = null;
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool fromMe;
  final DateTime? time;
  final bool pending;
  final bool seen;

  const _Bubble({
    required this.text,
    required this.fromMe,
    required this.time,
    required this.pending,
    required this.seen,
  });

  @override
  Widget build(BuildContext context) {
    final t = time;
    final stamp = t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: fromMe ? AppColors.brandGradient : null,
                  color: fromMe ? null : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(fromMe ? 20 : 6),
                    bottomRight: Radius.circular(fromMe ? 6 : 20),
                  ),
                ),
                child: Opacity(
                  opacity: pending ? 0.6 : 1,
                  child: Text(text, style: const TextStyle(fontSize: 15.5, height: 1.3)),
                ),
              ),
            ),
            if (pending || stamp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 6, right: 6),
                child: Text(
                  pending ? 'Sending…' : (seen ? '$stamp · Seen' : stamp),
                  style: TextStyle(fontSize: 11, color: seen ? AppColors.cyan : AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
