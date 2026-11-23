import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/press_scale.dart';
import '../widgets/shield_logo.dart';
import 'report_chat_engine.dart';

/// Larger type and taps for seniors / low tech comfort; everything else stays the same layout.
class ChatScale {
  const ChatScale({this.large = false});
  final bool large;
  double get body => large ? 18 : 15.5;
  double get chip => large ? 17 : 15;
  double get chipHeight => large ? 52 : 44;
}

/// Bot line: shield avatar + a bubble on the surface colour.
class BotBubble extends StatelessWidget {
  const BotBubble({super.key, this.text, this.child, this.scale = const ChatScale(), this.avatar = true});
  final String? text;
  final Widget? child;
  final ChatScale scale;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      SizedBox(width: 30, child: avatar ? const ShieldLogo(size: 28) : null),
      const SizedBox(width: Sp.s),
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
            ),
            boxShadow: Elev.card(Theme.of(context).brightness),
          ),
          child: child ??
              Text(text ?? '', style: TextStyle(fontSize: scale.body, height: 1.45, color: p.ink)),
        ),
      ),
      const SizedBox(width: 40),
    ]);
  }
}

/// The user's own answer, right-aligned in the accent colour. [voice] adds a small "spoken" tag.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text, this.voice = false, this.voiceTag = '', this.scale = const ChatScale()});
  final String text;
  final bool voice;
  final String voiceTag;
  final ChatScale scale;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      const SizedBox(width: 56),
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (voice)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mic_rounded, size: 14, color: p.onAccent.withValues(alpha: 0.85)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(voiceTag,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: p.onAccent.withValues(alpha: 0.85))),
                  ),
                ]),
              ),
            Text(text, style: TextStyle(fontSize: scale.body, height: 1.4, color: p.onAccent)),
          ]),
        ),
      ),
    ]);
  }
}

/// The warning the app already caught, shown inside the bot's first bubble.
class EvidenceChip extends StatelessWidget {
  const EvidenceChip({super.key, required this.time, required this.title, this.quote});
  final String time, title;
  final String? quote;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(time, style: TextStyle(fontSize: 13, color: p.muted)),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
        if (quote != null && quote!.isNotEmpty)
          Text('"$quote"', style: TextStyle(fontSize: 13, color: p.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Tap-to-answer pills under the current question. The first is filled when [primaryFirst] (Yes-type answers).
class QuickReplies extends StatelessWidget {
  const QuickReplies({super.key, required this.choices, required this.onPick, this.scale = const ChatScale()});
  final List<ChatChoice> choices;
  final ValueChanged<ChatChoice> onPick;
  final ChatScale scale;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
        for (final c in choices)
          PressScale(
            child: OutlinedButton(
              key: Key('chip_${c.value}'),
              onPressed: () => onPick(c),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(48, scale.chipHeight),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: const StadiumBorder(),
                side: BorderSide(color: p.accent, width: 1.5),
                backgroundColor: p.surface,
                foregroundColor: p.accent,
                textStyle: TextStyle(fontSize: scale.chip, fontWeight: FontWeight.w600),
              ),
              child: Text(c.label, textAlign: TextAlign.center),
            ),
          ),
      ]),
    );
  }
}

/// Thumbnails (images) or file tiles for what the user attached, right-aligned like their answers.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.files});
  final List<ChatAttachment> files;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
        for (final f in files)
          Container(
            width: 84,
            height: 104,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: f.isImage && File(f.path).existsSync()
                ? Semantics(
                    image: true,
                    label: f.name,
                    child: Image.file(File(f.path), fit: BoxFit.cover, cacheWidth: 200),
                  )
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(f.mime.startsWith('audio/') ? Icons.graphic_eq_rounded : Icons.description_outlined,
                          color: p.muted, size: 24),
                      const SizedBox(height: 4),
                      Text(f.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.muted)),
                    ]),
                  ),
          ),
      ]),
    );
  }
}

/// Three soft dots while Gemma rewords the next question.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key, required this.label});
  final String label;
  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Semantics(
      label: widget.label,
      child: BotBubble(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.muted.withValues(alpha: 0.35 + 0.65 * ((((_c.value * 3) - i) % 3) < 1 ? 1 : 0)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Mic is open: a live waveform, the words heard so far, and a red stop button.
class ListeningPanel extends StatelessWidget {
  const ListeningPanel({
    super.key,
    required this.partial,
    required this.levels,
    required this.caption,
    required this.stopLabel,
    required this.onStop,
    this.scale = const ChatScale(),
  });
  final String partial, caption, stopLabel;
  final List<double> levels;
  final VoidCallback onStop;
  final ChatScale scale;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.m, Sp.xs, Sp.m, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(RadX.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: ExcludeSemantics(
              child: SizedBox(
                height: 40,
                child: Row(children: [
                  for (final l in levels)
                    Expanded(
                      child: Align(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: 6 + 34 * l.clamp(0.0, 1.0),
                          decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: Sp.m),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filled(
              key: const Key('btn_mic_stop'),
              tooltip: stopLabel,
              onPressed: onStop,
              style: IconButton.styleFrom(backgroundColor: st.scam, foregroundColor: Colors.white),
              icon: const Icon(Icons.stop_rounded, size: 26),
            ),
          ),
        ]),
        if (partial.isNotEmpty) ...[
          const SizedBox(height: Sp.s),
          Text('"$partial"', key: const Key('mic_partial'), style: TextStyle(fontSize: scale.body + 1, color: p.ink)),
        ],
        const SizedBox(height: Sp.xs),
        Text(caption, style: TextStyle(fontSize: 13, color: p.muted)),
      ]),
    );
  }
}

/// Attach · text field · mic. Send replaces the mic once there is text.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.attachLabel,
    required this.micLabel,
    required this.sendLabel,
    required this.onAttach,
    required this.onMic,
    required this.onSend,
    this.numeric = false,
    this.focusNode,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint, attachLabel, micLabel, sendLabel;
  final VoidCallback onAttach, onMic, onSend;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    Widget round(Key key, String tip, IconData icon, VoidCallback onTap, {required Color bg, required Color fg}) =>
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: key,
            tooltip: tip,
            onPressed: onTap,
            style: IconButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
            icon: Icon(icon, size: 24),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.m, Sp.s, Sp.m, Sp.xs),
      child: Row(children: [
        round(const Key('btn_attach'), attachLabel, Icons.attach_file_rounded, onAttach, bg: p.surfaceAlt, fg: p.ink),
        const SizedBox(width: Sp.s),
        Expanded(
          child: TextField(
            key: const Key('chat_input'),
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 4,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: TextStyle(fontSize: 15.5, color: p.ink),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: p.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.pill), borderSide: BorderSide(color: p.hairline)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.pill), borderSide: BorderSide(color: p.hairline)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.pill), borderSide: BorderSide(color: p.accent, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: Sp.s),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, _) => v.text.trim().isEmpty
              ? round(const Key('btn_mic'), micLabel, Icons.mic_rounded, onMic, bg: p.accentTint, fg: p.accent)
              : round(const Key('btn_send'), sendLabel, Icons.arrow_upward_rounded, onSend, bg: p.accent, fg: p.onAccent),
        ),
      ]),
    );
  }
}

/// "Your report is ready": the filled-in details plus the actions that send them.
class ReportSummaryCard extends StatelessWidget {
  const ReportSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.editLabel,
    required this.rows,
    required this.onEdit,
    required this.actions,
  });
  final String title, subtitle, editLabel;
  final List<(String, String)> rows;
  final VoidCallback onEdit;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Container(
      key: const Key('report_summary'),
      padding: const EdgeInsets.all(Sp.l),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(RadX.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.task_outlined, color: p.accent, size: 22),
          const SizedBox(width: Sp.s),
          Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink))),
          TextButton(
            key: const Key('btn_edit_report'),
            onPressed: onEdit,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: p.accent),
            child: Text(editLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
        Text(subtitle, style: TextStyle(fontSize: 13, color: p.muted)),
        const SizedBox(height: Sp.m),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Wrap(spacing: Sp.m, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(k, style: TextStyle(fontSize: 14, color: p.muted)),
              ),
              Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink)),
            ]),
          ),
        const SizedBox(height: Sp.s),
        for (final a in actions) Padding(padding: const EdgeInsets.only(top: Sp.s), child: a),
      ]),
    );
  }
}
