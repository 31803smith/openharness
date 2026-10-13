/// Every word of the phone's onboarding, in one place — the "Every word" table of
/// `docs/research/2026-10-11-phone-onboarding` (agreed with the owner, 2026-10-12).
///
/// ```
/// ① Welcome        Manage all your agents on all your computers from your phone.
///                  [Scan QR from computer] [Continue with Google] [Continue with Apple]
///                  Scan QR from computer → the camera: How to get the QR code, its steps,
///                  Use email instead
/// ② Your computer  On your computer, go to   [autonomous.ai/go ⇪]
///                  under the picture: Looking for your computer▌
///                  under the link: (1) Install Harness  (2) Sign in, Use you@…
///                  under the account: Not you? Sign out
///   The Mac joins  MacBook Pro is ready.
/// ③ The session    by the mic, once: Send it, or say anything.
/// ```
///
/// ⚠️ **One source, because the screens share one story.** The same step is named the same way on
/// every screen it appears on — the welcome, Computers ▸ Add computer, the desktop's `/go` page — and
/// a word changed here is changed everywhere the phone says it. The desktop's own words (its pane
/// title's hover line, "✓ Added by …" at the end of its tour) are the desktop's; keep them in step
/// with these.
///
/// ⚠️ **Nothing else on these screens** (owner, 2026-10-12): no sample link, no tips, no notification
/// prompt, no page dots, and never the word "network". ② says what to do on the computer — which
/// account to sign in with, and where Add Phone is (owner, 2026-10-12, after trying it):
/// until the phone adds the computer itself, the computer signs in on its own, and that is where
/// people stood stuck.
abstract final class OnboardingCopy {
  /// ① The welcome's headline: everything lit, the promise.
  static const welcome =
      'Manage all your agents on all your computers from your phone.';

  /// ① The first of the three ways in: the camera, for the code a signed-in computer's Add Phone
  /// shows, which signs this phone in to that computer's account with nothing to type.
  static const scanQrCode = 'Scan QR from computer';

  /// An emailed code. Not on the welcome any more (owner, 2026-10-12: three ways in, nothing else);
  /// the camera's "Use email instead" leads to it.
  static const continueWithEmail = 'Continue with email';

  /// ① Under the picture, when the camera read a computer's own sign-in code (its "Scan with your
  /// phone"): this phone needs an account before it can approve one.
  static const signInFirst = 'Sign in first, then approve your computer.';

  /// ② The headline over the address.
  static const goToHeadline = 'On your computer, go to';

  /// ② The address, as written on the button that sends it: short enough to type off the phone.
  static const goAddress = 'autonomous.ai/go';

  /// ② The address the button sends — the download for whatever computer opens it. The main site
  /// sends `/go` on to Harness's download page (`harness.autonomous.ai/desktop`), which picks the
  /// file for the computer that opens it.
  static const goUrl = 'https://autonomous.ai/go';

  /// ② Under the picture, while the laptop breathes.
  static const looking = 'Looking for your computer';

  /// ② The first step under the link: installing Harness — the link above it is the download, so
  /// the step need not say so (`set_up_computer.dart`'s [goToSteps]; the second is signing in with
  /// this account).
  static const installStep = 'Install Harness';

  /// ② Right under the account the steps name, at home: the question, and the way out after it.
  static const notYou = 'Not you?';
  static const signOut = 'Sign out';

  /// The moment the computer joins — its own name, as the account knows it.
  static String ready(String computer) => '$computer is ready.';

  /// Under "… is ready.", past the moment, while the computer has no session yet — its own tour
  /// starts one. Not the spec's: its computer always had one by then.
  static const waitingForSession = 'Waiting for its first session';

  /// What the phone says by the mic the first time it opens a session — one line, once.
  static const micSendIt = 'Send it, or say anything.';
  static const micPickUp = 'Pick up where you left off.';
  static const micSayWhat = 'Say what to build.';
  static const micTalk = 'Talk to it.';
}
