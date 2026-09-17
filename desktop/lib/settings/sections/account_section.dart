import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/setting_row.dart';
import '../../state/app_state.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      final local = notifier.localManualFixture != null;
      final guest = notifier.isGuest;
      final profile = notifier.currentUser;
      // A guest's row says what the account is FOR and offers it; the sheet
      // opens over Settings, which stays where it is — there is nothing to
      // leave, and the row rewrites itself the moment the account arrives.
      if (guest) {
        return SectionScaffold(
          title: 'Account',
          subtitle:
              'This computer works without one. An account reaches your '
              'other machines and voice on the dial.',
          child: SingleChildScrollView(
            child: SettingRow(
              title: 'Not signed in',
              detail: 'Sign in to reach your other machines',
              control: FilledButton(
                key: const Key('settings-sign-in-button'),
                onPressed: () => showSignInSheet(context, notifier),
                child: const Text('Sign in'),
              ),
            ),
          ),
        );
      }
      return SectionScaffold(
        title: 'Account',
        subtitle: local
            ? 'Connected to a local development session.'
            : 'Your Harness sign-in on this computer.',
        child: SingleChildScrollView(
          child: SettingRow(
            title:
                profile?.displayName ?? (local ? 'Local session' : 'Signed in'),
            detail:
                profile?.email ??
                (local ? 'Loopback backend' : 'Profile unavailable'),
            control: OutlinedButton(
              key: const Key('settings-sign-out-button'),
              onPressed: () {
                Navigator.of(context).pop();
                notifier.logout();
              },
              child: Text(local ? 'Disconnect local session' : 'Sign out'),
            ),
          ),
        ),
      );
    },
  );
}
