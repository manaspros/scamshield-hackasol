/// In-call signal kinds as the Kotlin side emits them in the 'signal' event (InCallSignals.KIND_*).
/// test/live_signals_test.dart compares this list with the Kotlin source, so change both together.
abstract final class SignalKinds {
  static const otp = 'otp_during_call';
  static const remoteApp = 'remote_app_during_call';
  static const paymentApp = 'payment_app_during_call';
  static const screenShare = 'screen_share_during_call';
  static const appInstalled = 'app_installed_during_call';

  static const all = {otp, remoteApp, paymentApp, screenShare, appInstalled};
}
