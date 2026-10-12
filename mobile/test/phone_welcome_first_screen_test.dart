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

/// The first screen: ① Welcome — the promise, Scan QR code and the two accounts, and nothing else
/// (`docs/research/2026-10-11-phone-onboarding`; owner, 2026-10-12). The emailed code is the
/// camera's "Use email instead".
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

  TtyPrimaryButton scan(WidgetTester tester) => tester.widget<TtyPrimaryButton>(
    find.byKey(const ValueKey('welcome-scan')),
  );

  SignInProviderButton account(WidgetTester tester, SignInProvider provider) =>
      tester
          .widgetList<SignInProviderButton>(find.byType(SignInProviderButton))
          .firstWhere((button) => button.provider == provider);

  testWidgets(
    'the promise, Scan QR code and the two accounts — and nothing else',
    (tester) async {
      await pump(tester);
      expect(find.text(OnboardingCopy.welcome), findsOneWidget);
      expect(
        tester.widget<OnboardingPicture>(find.byType(OnboardingPicture)).scene,
        OnboardingScene.welcome,
      );
      expect(find.text(OnboardingCopy.scanQrCode), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
      // The emailed code is the camera's, not this screen's.
      expect(find.text(OnboardingCopy.continueWithEmail), findsNothing);
      // Scan QR code first, then Google, then Apple.
      expect(
        tester.getTopLeft(find.text(OnboardingCopy.scanQrCode)).dy,
        lessThan(tester.getTopLeft(find.text('Continue with Google')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Continue with Google')).dy,
        lessThan(tester.getTopLeft(find.text('Continue with Apple')).dy),
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
      expect(find.byKey(const ValueKey('welcome-cancel')), findsOneWidget);
      // The other account, and the camera, wait it out.
      expect(account(tester, SignInProvider.apple).onPressed, isNull);
      expect(scan(tester).onPressed, isNull);
      // The foot is the same height whatever it says: the picture has not moved.
      expect(picture(tester), before);

      // Past the page, going in: nothing left to cancel, and a scan cannot sign in behind it.
      notifier.status = AppStatus.bootstrapping;
      notifier.notifyListeners();
      await tester.pump();
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byKey(const ValueKey('welcome-cancel')), findsNothing);
      expect(scan(tester).onPressed, isNull);
      expect(picture(tester), before);
    },
  );

  testWidgets('why the phone was signed out is said under the picture', (
    tester,
  ) async {
    await pump(tester);
    final before = picture(tester);
    notifier.signedOutReason = 'You were signed out on another device.';
    notifier.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('welcome-signed-out')), findsOneWidget);
    expect(
      find.textContaining('You were signed out on another device.'),
      findsOneWidget,
    );
    expect(picture(tester), before);
  });

  testWidgets('the emailed code: the address, then the four digits, and back', (
    tester,
  ) async {
    await pump(tester);
    // Through the camera: Scan QR code, then its "Use email instead".
    await tester.tap(find.byKey(const ValueKey('welcome-scan')));
    await tester.pump();
    expect(find.byType(ScanToConnectPage), findsOneWidget);
    await tester.tap(find.text('Use email instead'));
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
