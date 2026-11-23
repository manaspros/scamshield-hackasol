import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Reduced motion: [d], or zero when the user turned animations off
/// (Android "Remove animations", iOS "Reduce Motion").
Duration motion(BuildContext context, Duration d) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : d;

/// How long a self-dismissing message stays up: at least 10 s while a screen reader
/// (TalkBack / VoiceOver) is navigating, so it can be reached and read in full.
Duration readingTime(BuildContext context, Duration d) {
  const min = Duration(seconds: 10);
  final sr = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
  return sr && d < min ? min : d;
}

/// Speaks [message] on platforms that accept announcement events (iOS, web).
/// Android reports no announce support (TalkBack deprecated it); there the live region in
/// [LiveAnnounce] is what TalkBack reads.
void announce(BuildContext context, String message) {
  if (message.isEmpty || !MediaQuery.supportsAnnounceOf(context)) return;
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.maybeOf(context) ?? TextDirection.ltr,
  );
}

/// Wraps a result card so a screen reader speaks [message] (headline + first advice line) when it
/// first appears and whenever [message] changes, never on a plain rebuild. Give it a new key to
/// announce the same message again (a fresh check that gave the same verdict).
class LiveAnnounce extends StatefulWidget {
  const LiveAnnounce({super.key, required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  State<LiveAnnounce> createState() => _LiveAnnounceState();
}

class _LiveAnnounceState extends State<LiveAnnounce> {
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(LiveAnnounce old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) _schedule();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) announce(context, widget.message);
    });
  }

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true, // Android: a new node or a changed label is read by TalkBack
        label: widget.message,
        child: widget.child,
      );
}
