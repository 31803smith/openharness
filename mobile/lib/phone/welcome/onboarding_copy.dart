/// Every word of the phone's onboarding, in one place — the "Every word" table of
/// `docs/research/2026-10-11-phone-onboarding` (agreed with the owner, 2026-10-12).
///
/// ```
/// ① Welcome        Manage all your agents on all your computers from your phone.
///                  [Continue with Google] [Continue with Apple]   Continue with email
/// ② Your computer  On your computer, go to   [autonomous.ai/go ⇪]
///                  under the picture: Looking for your computer▌
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
/// prompt, no fallback lines, no page dots, and never the word "network".
abstract final class OnboardingCopy {
  /// ① The welcome's headline: everything lit, the promise.
  static const welcome =
      'Manage all your agents on all your computers from your phone.';

  /// ① The quiet line under the accounts.
  static const continueWithEmail = 'Continue with email';

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
