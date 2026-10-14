import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/auth/sign_in_provider.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/phone/tty_controls.dart';
import 'package:harness_mobile/phone/welcome/connect_code.dart';
import 'package:harness_mobile/phone/welcome/onboarding_copy.dart';
import 'package:harness_mobile/phone/welcome/onboarding_picture.dart';
import 'package:harness_mobile/phone/welcome/phone_welcome.dart';
import 'package:harness_mobile/phone/welcome/scan_to_connect.dart';
import 'package:harness_mobile/phone/welcome/sign_in_provider_button.dart';
import 'package:harness_mobile/state/app_state.dart';

/// The first screen: ① Welcome — the promise, the two accounts, and under them one quiet line:
/// Continue with email · QR code (owner, 2026-10-14; it was Scan QR code first, then the two
/// accounts, on 2026-10-12, `docs/research/2026-10-11-phone-onboarding`).
void main() {
  group('ConnectCode', () {
    test('reads the desktop app\'s link, all of it in the fragment', () {
      final code = ConnectCode.parse(
        ConnectCode.link('ada@example.com', machineId: 'm1', pairCode: 'K7QM'),
      )!;
      expect(code.email, 'ada@example.com');
      expect(code.machineId, 'm1');
      expect(code.pairCode, 'K7QM');
      expect(code.signIn, isNull);
      final signedIn = ConnectCode.parse(
        ConnectCode.link(
          'ada@example.com',
          pairCode: 'K7QM',
          signIn: 'hnh_x-_Y',
        ),
      )!;
      expect(signedIn.signIn, 'hnh_x-_Y');
      // Nothing secret where a browser would send it.
      expect(
        Uri.parse(ConnectCode.link('a@b.co', pairCode: 'K7QM')).query,
        isEmpty,
      );
    });

    test('ignores codes that are not ours', () {
      expect(ConnectCode.parse('https://example.com/pair#e=a@b.co'), isNull);
      expect(
        ConnectCode.parse('http://harness.autonomous.ai/pair#e=a@b.co'),
        isNull,
      );
      expect(
        ConnectCode.parse('https://harness.autonomous.ai/pair#m=m1'),
        isNull,
      );
      expect(ConnectCode.parse('not a link'), isNull);
    });
  });

  late AppNotifier notifier;
  late List<String> sent;
  late List<(String, String)> signedIn;

  setUp(() {
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    sent = [];
    signedIn = [];
  });
  tearDown(() => notifier.dispose());

  /// The welcome as the app mounts it: rebuilt whenever the notifier moves (`RootShell`).
  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: notifier,
          builder: (_, _) => PhoneWelcome(
            notifier: notifier,
            sendCode: (email) async => sent.add(email),
            signIn: (email, code) async => signedIn.add((email, code)),
            scanCamera: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect picture(WidgetTester tester) =>
      tester.getRect(find.byType(OnboardingPicture));

  final email = find.byKey(const ValueKey('welcome-continue-email'));
  final scan = find.byKey(const ValueKey('welcome-scan'));

  SignInProviderButton account(WidgetTester tester, SignInProvider provider) =>
      tester
          .widgetList<SignInProviderButton>(find.byType(SignInProviderButton))
          .firstWhere((button) => button.provider == provider);

  testWidgets(
    'the promise, the two accounts, then Continue with email · QR code — and nothing else',
    (tester) async {
      await pump(tester);
      expect(find.text(OnboardingCopy.welcome), findsOneWidget);
      expect(
        tester.widget<OnboardingPicture>(find.byType(OnboardingPicture)).scene,
        OnboardingScene.welcome,
      );
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text(OnboardingCopy.continueWithEmail), findsOneWidget);
      expect(find.text(OnboardingCopy.qrCode), findsOneWidget);
      // The camera's long name is what a screen reader hears, not what the line says.
      expect(find.text(OnboardingCopy.scanQrCode), findsNothing);
      // Only the accounts are buttons; the lesser ways in are words.
      expect(find.byType(TtyPrimaryButton), findsNothing);
      // Google, then Apple, then the quiet line — email and QR code side by side on it.
      expect(
        tester.getTopLeft(find.text('Continue with Google')).dy,
        lessThan(tester.getTopLeft(find.text('Continue with Apple')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Continue with Apple')).dy,
        lessThan(tester.getTopLeft(email).dy),
      );
      expect(tester.getCenter(email).dy, tester.getCenter(scan).dy);
      expect(
        tester.getCenter(email).dx,
        lessThan(tester.getCenter(scan).dx),
      );

      // Not the camera, the sample, or the steps on the computer of the first screen before it.
      expect(find.byType(ScanToConnectPage), findsNothing);
      expect(find.text('Connect computer'), findsNothing);
      expect(find.text('Can’t scan? Sign in another way'), findsNothing);
      expect(find.text('Try the sample while you wait'), findsNothing);
      expect(find.text('Your agents\nin your pocket.'), findsNothing);
    },
  );

  testWidgets(
    'an account\'s page up: its button says so, and Cancel takes the quiet line',
    (tester) async {
      await pump(tester);
      final before = picture(tester);

      notifier
        ..signingIn = true
        ..signInProvider = SignInProvider.google
        ..status = AppStatus.unauthenticated;
      notifier.notifyListeners();
      await tester.pump();
      expect(find.text('Waiting for Google…'), findsOneWidget);
      // Cancel takes the quiet line's place: email and the camera could not be pressed now.
      expect(find.byKey(const ValueKey('welcome-cancel')), findsOneWidget);
      expect(email, findsNothing);
      expect(scan, findsNothing);
      // The other account waits it out.
      expect(account(tester, SignInProvider.apple).onPressed, isNull);
      // The foot is the same height whatever it says: the picture has not moved.
      expect(picture(tester), before);

      // Past the page, going in: nothing left to cancel; the quiet line is back, and neither an
      // email nor a scan can sign in behind it.
      notifier.status = AppStatus.bootstrapping;
      notifier.notifyListeners();
      await tester.pump();
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byKey(const ValueKey('welcome-cancel')), findsNothing);
      await tester.tap(scan);
      await tester.pump();
      expect(find.byType(ScanToConnectPage), findsNothing);
      await tester.tap(email);
      await tester.pump();
      expect(find.text('Your email'), findsNothing);
      expect(picture(tester), before);
    },
  );

  testWidgets('why the phone was signed out is said under the headline', (
    tester,
  ) async {
    await pump(tester);
    final before = picture(tester);
    notifier.signedOutReason = 'You were signed out on another device.';
    notifier.notifyListeners();
    await tester.pump();
    final said = find.byKey(const ValueKey('welcome-signed-out'));
    expect(said, findsOneWidget);
    expect(
      find.textContaining('You were signed out on another device.'),
      findsOneWidget,
    );
    // Between the headline and the picture, on the headline's left edge.
    final headline = tester.getRect(
      find.byKey(const ValueKey('welcome-headline')),
    );
    final line = tester.getRect(said);
    expect(line.top, greaterThan(headline.bottom));
    expect(line.left, headline.left);
    expect(line.bottom, lessThanOrEqualTo(before.top));
    expect(picture(tester), before);
  });

  testWidgets('QR code: the camera, with no "Use email instead" — back is the way out', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(scan);
    await tester.pump();
    expect(find.byType(ScanToConnectPage), findsOneWidget);
    // Continue with email is beside QR code on the welcome, one back away (owner, 2026-10-14).
    expect(find.text('Use email instead'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(OnboardingCopy.welcome), findsOneWidget);
    expect(email, findsOneWidget);
  });

  testWidgets('the emailed code: the address, then the four digits, and back', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(email);
    await tester.pump();
    expect(find.text('Your email'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    await tester.pump();
    expect(sent, ['ada@example.com']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('ada@example.com'), findsOneWidget);

    // The last digit signs in by itself.
    await tester.enterText(find.byType(TextField), '4242');
    await tester.pump();
    await tester.pump();
    expect(signedIn, [('ada@example.com', '4242')]);

    // Back from the code is the email, and back from that the welcome.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Your email'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(OnboardingCopy.welcome), findsOneWidget);

    // The resend clock runs out before the test ends.
    await tester.pump(const Duration(seconds: 31));
  });
}
