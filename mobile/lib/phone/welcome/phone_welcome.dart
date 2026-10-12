import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/auth/sign_in_provider.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/app_state.dart';

import '../exit_app.dart';
import '../tty.dart';
import '../tty_controls.dart';
import 'email_sign_in.dart';
import 'onboarding_copy.dart';
import 'onboarding_frame.dart';
import 'onboarding_picture.dart';
import 'sign_in_provider_button.dart';

/// The phone's first screen, signed out: ① Welcome — the promise, and signing in right there.
///
/// ```
///
///   Manage all your agents on all
///   your computers from your phone.
///
///        ┌─────────────────────┐
///        │  three computers,   │      everything lit: agents typing, packets running to the phone
///        │  all lit, a phone   │
///        └─────────────────────┘
///
///   [ G  Continue with Google ]
///   [   Continue with Apple   ]
///        Continue with email        → Your email → Check your email
/// ```
///
/// Signing in is all there is to do here, and it moves on by itself: signed in, the app swaps this
/// for home, which says "On your computer, go to" when the account has no computer yet and opens
/// the computer's session when it has one (`docs/research/2026-10-11-phone-onboarding`, agreed with
/// the owner 2026-10-12).
///
/// ⚠️ **Google first, and nothing else on the screen** (owner, 2026-10-12): no camera, no sample, no
/// "Is Harness on your computer?", no tips. The QR the desktop shows only gets the app now — the
/// account does the rest, its device key log making every computer signed in to it trust this phone
/// — so the camera this screen used to open on (2026-10-09) has nothing left to read here.
///
/// ⚠️ **The foot never changes height.** While an account's page is up, the quiet line under the
/// buttons becomes Cancel; why it did not finish is said under the picture — so the picture, in
/// the same place on every onboarding screen ([OnboardingFrame]), never moves for it.
class PhoneWelcome extends StatefulWidget {
  const PhoneWelcome({
    super.key,
    required this.notifier,
    this.sendCode,
    this.signIn,
  });

  final AppNotifier notifier;

  /// Stand-ins for the account service, for tests and renders. Null uses [notifier]'s.
  final Future<void> Function(String email)? sendCode;
  final Future<void> Function(String email, String code)? signIn;

  @override
  State<PhoneWelcome> createState() => _PhoneWelcomeState();
}

enum _Step { hello, email, code }

class _PhoneWelcomeState extends State<PhoneWelcome> {
  _Step _step = _Step.hello;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  String? _sentTo;
  bool _busy = false;

  String? _error;
  int _resendIn = 0;
  Timer? _resendTimer;

  static const _codeLength = 4;
  static const _resendAfter = 30;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// "Continue with Google / Apple": the account's own sign-in page, in the app. Its failure is
  /// said under the picture; a cancel says nothing ([AppNotifier.signInWithProvider]).
  Future<void> _signInWith(SignInProvider provider) async {
    if (widget.notifier.signingIn) return;
    setState(() => _error = null);
    try {
      await widget.notifier.signInWithProvider(provider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _plain(e.toString()));
    }
  }

  /// To [step], with nothing said on it unless [error] is: a step's failure belongs to the step
  /// it happened on.
  void _go(_Step step, {String? error}) {
    // Leaving for another way in takes the account's page with it: whatever it came back with
    // would sign the phone in behind the step the person chose instead.
    if (step != _step) widget.notifier.cancelProviderSignIn();
    setState(() {
      _step = step;
      _error = error;
    });
    if (step == _Step.email) _emailFocus.requestFocus();
    if (step == _Step.code) _codeFocus.requestFocus();
    if (step == _Step.hello) FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Emails a code to the address in the field and moves on to it. False when it did not go, with
  /// the reason in [_error].
  Future<bool> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'That doesn’t look like an email address.');
      return false;
    }
    final from = _step;
    final ok = await _run(
      () => (widget.sendCode ?? widget.notifier.sendLoginCode)(email),
    );
    if (!mounted) return false;
    if (!ok) {
      // Nor its failure, under a step that is not about the email.
      if (_step != from) setState(() => _error = null);
      return false;
    }
    _sentTo = email;
    _code.clear();
    _startResend();
    // ⚠️ On from the step it was sent from only: back pressed while it went must not have the
    // first screen jump to "Check your email" a second later.
    if (_step == from) _go(_Step.code);
    return true;
  }

  Future<void> _signIn() async {
    final email = _sentTo, code = _code.text.trim();
    if (email == null) return;
    if (code.length < _codeLength) {
      setState(() => _error = 'Enter the $_codeLength digits from the email.');
      return;
    }
    await _run(
      () => widget.signIn != null
          ? widget.signIn!(email, code)
          : widget.notifier.signInWithCode(email: email, code: code),
    );
  }

  Future<bool> _run(Future<void> Function() request) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await request();
    } catch (e) {
      error = _plain(e.toString());
    }
    if (!mounted) return false;
    setState(() {
      _busy = false;
      _error = error;
    });
    return error == null;
  }

  /// A service's reason, without the exception's type in front of it.
  static String _plain(String raw) =>
      raw.replaceFirst(RegExp(r'^(Exception|StateError|Bad state):\s*'), '');

  void _startResend() {
    _resendTimer?.cancel();
    _resendIn = _resendAfter;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  /// Where back goes from [step] — the system's back and each page's own `‹ Back` alike.
  _Step _backFrom(_Step step) => switch (step) {
    _Step.code => _Step.email,
    _ => _Step.hello,
  };

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final tty = Tty.of(context);
    final notifier = widget.notifier;
    final signingIn = notifier.signingIn;
    // Past the page and the exchange, the session is saved and the machines are on their way:
    // nothing is waited on in the browser any more, and nothing to cancel.
    final entering = signingIn && notifier.status == AppStatus.bootstrapping;
    return PopScope(
      // The first screen lets the press go to the system — except on Android, which asks before
      // the app is left ([confirmExitApp]) and so keeps it here too.
      canPop: !confirmsExitOnBack && _step == _Step.hello,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step == _Step.hello) {
          unawaited(confirmExitApp(context));
          return;
        }
        _go(_backFrom(_step));
      },
      child: Scaffold(
        backgroundColor: tty.ground,
        body: SafeArea(
          child: switch (_step) {
            _Step.hello => OnboardingFrame(
              headline: OnboardingCopy.welcome,
              headlineKey: const ValueKey('welcome-headline'),
              picture: const OnboardingPicture(scene: OnboardingScene.welcome),
              status: switch ((_error, notifier.signedOutReason)) {
                (final error?, _) => _Said(error, error: true),
                (null, final reason?) => _Said(reason),
                _ => null,
              },
              actions: _Accounts(
                onProvider: signingIn
                    ? null
                    : (provider) => unawaited(_signInWith(provider)),
                waitingOn: notifier.signInProvider,
                entering: entering,
                onCancel: notifier.cancelProviderSignIn,
                onEmail: () => _go(_Step.email),
              ),
            ),
            _Step.email => SignInForm(
              onBack: () => _go(_backFrom(_Step.email)),
              title: 'Your email',
              lines: const ['We’ll send you a $_codeLength-digit code.'],
              field: TtyField(
                key: const Key('welcome-email'),
                controller: _email,
                focus: _emailFocus,
                hint: 'you@example.com',
                action: TextInputAction.go,
                onSubmitted: _sendCode,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              error: _error,
              button: TtyPrimaryButton(
                label: 'Send code',
                busy: _busy,
                busyLabel: 'Sending…',
                onPressed: _sendCode,
              ),
            ),
            _Step.code => SignInForm(
              onBack: () => _go(_Step.email),
              title: 'Check your email',
              lines: [
                'We sent a $_codeLength-digit code to ${_sentTo ?? 'your email'}.',
              ],
              field: SignInCodeField(
                controller: _code,
                focus: _codeFocus,
                length: _codeLength,
                onFilled: _signIn,
              ),
              error: _error,
              button: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _code,
                builder: (_, value, _) => TtyPrimaryButton(
                  label: 'Sign in',
                  busy: _busy || signingIn,
                  busyLabel: 'Signing in…',
                  onPressed: value.text.trim().length == _codeLength
                      ? _signIn
                      : null,
                ),
              ),
              footer: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TtyTextButton(
                      label: _resendIn > 0
                          ? 'Resend in ${_resendIn}s'
                          : 'Resend code',
                      onPressed: _resendIn > 0 || _busy ? null : _sendCode,
                    ),
                  ),
                  Flexible(
                    child: TtyTextButton(
                      label: 'Change email',
                      onPressed: _busy ? null : () => _go(_Step.email),
                    ),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// The welcome's foot: Google, then Apple ([SignInProviderButton]), and the quiet line under them —
/// "Continue with email", or Cancel while an account's page is up. One slot for both, so the foot
/// is the same height whatever it says.
class _Accounts extends StatelessWidget {
  const _Accounts({
    required this.onProvider,
    required this.onCancel,
    required this.onEmail,
    this.waitingOn,
    this.entering = false,
  });

  /// "Continue with …" pressed. Null while any sign-in is in flight, which both buttons wait out.
  final ValueChanged<SignInProvider>? onProvider;

  /// The account whose page is up — its button says so, and Cancel takes the quiet line.
  final SignInProvider? waitingOn;

  /// The page is done with and the phone is going in: the button says so, and there is nothing
  /// left to cancel.
  final bool entering;
  final VoidCallback onCancel;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final waiting = waitingOn != null && !entering;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in SignInProvider.values) ...[
          if (provider != SignInProvider.values.first)
            const SizedBox(height: 10),
          SignInProviderButton(
            provider: provider,
            onPressed: onProvider == null ? null : () => onProvider!(provider),
            busyLabel: provider == waitingOn
                ? (entering ? 'Signing in…' : 'Waiting for ${provider.label}…')
                : null,
          ),
        ],
        Center(
          child: waiting
              ? TtyTextButton(
                  key: const ValueKey('welcome-cancel'),
                  label: 'Cancel',
                  size: TtySize.meta,
                  onPressed: onCancel,
                )
              : TtyTextButton(
                  key: const ValueKey('welcome-email-way'),
                  label: OnboardingCopy.continueWithEmail,
                  size: TtySize.meta,
                  color: tty.faint,
                  // Not while an account's page is up, or past it: the email would sign in
                  // behind it.
                  onPressed: onProvider == null ? null : onEmail,
                ),
        ),
      ],
    );
  }
}

/// A line under the picture, in the status line's place: why an account's sign-in did not finish
/// (the terminal's red ✗), or why a phone that was signed in is back here (the sign-out mark in its
/// yellow — not red: the person did nothing wrong, and signing in again is the whole of what to do).
class _Said extends StatelessWidget {
  const _Said(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final style = tty.style(size: OnboardingFrame.quietSize);
    return Semantics(
      liveRegion: true,
      child: Text.rich(
        key: ValueKey(error ? 'welcome-error' : 'welcome-signed-out'),
        TextSpan(
          children: [
            if (error)
              const TextSpan(text: '✗ ')
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    LucideIcons.logOut300,
                    size: 14,
                    color: tty.yellow,
                  ),
                ),
              ),
            TextSpan(text: text),
          ],
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: error ? tty.red : tty.text),
      ),
    );
  }
}
