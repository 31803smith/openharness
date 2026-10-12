import 'package:flutter/material.dart';

import '../tty.dart';
import '../tty_controls.dart';
import 'scan_to_connect.dart' show kAddPhoneWhere;

/// The steps on a computer that bring up its Add Phone QR code — for the camera opened from
/// Computers, which pairs with a desktop from before the onboarding of 2026-10-12.
///
/// ⚠️ This file used to be **Connect your computer**, the page a phone with no computer stood on
/// (signed out, signed in with none, and Computers ▸ Set up another computer). The onboarding
/// replaced it (`docs/research/2026-10-11-phone-onboarding`): signed out, the welcome signs in
/// (`phone_welcome.dart`); with no computer, "On your computer, go to" (`your_computer.dart`). Only
/// the steps are left, for the camera's sake.

/// The first step on the computer, signed in or out.
const _openHarness = 'Open Harness on your computer';

/// The steps after [_openHarness]: sign in on the computer, then Add Phone and where it is.
///
/// ⚠️ **One set, wherever they are shown (owner, 2026-10-12)** — now only the camera's, from
/// Computers. They used to be two: signed out "Click
/// Add Phone ③ Scan the QR code", signed in "Sign in on your computer ③ Not showing up? Click Add
/// Phone" — one button on one page, and steps that changed under it, and on the camera "Not showing
/// up?" was asked of somebody already scanning. Both halves hold either way: Add Phone asks a
/// computer that is not signed in to sign in before it shows a code, and a computer that turns up
/// by itself is paired just as well by its code. The scan is the button above the steps, and the
/// camera's own title, so it is not a step of its own.
///
/// [signIn]: under signing in, which account — the phone's, when it has one to name. Null signed
/// out, where the scan signs the phone in to whichever account the computer has.
List<({String title, String? note})> _stepsAfterOpening(String? signIn) => [
  (title: 'Sign in on your computer', note: signIn),
  (title: 'Click Add Phone', note: kAddPhoneWhere),
];

/// The steps on the computer under the camera, opened from Computers ▸ "Or scan the QR code on your
/// computer" — where the page it came from says none of them ([ScanToConnectPage.steps]).
///
/// For a desktop from before the onboarding of 2026-10-12, which still pairs a phone by its Add
/// Phone QR code; every other computer is added by "On your computer, go to" (`your_computer.dart`).
class ComputerSteps extends StatelessWidget {
  const ComputerSteps({super.key, required this.account});

  /// This phone's account, named in the sign-in step.
  final String? account;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    final next = _stepsAfterOpening(account == null ? null : 'With $account.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _HowItWorksRow(number: 1, title: _openHarness),
        for (final (i, step) in next.indexed)
          _HowItWorksRow(
            number: i + 2,
            title: step.title,
            note: step.note,
            last: i == next.length - 1,
          ),
      ],
    );
  }
}

/// One step: its number in a ring, a thread down to the next one's, what to do, and under it a
/// quieter line when one is needed.
class _HowItWorksRow extends StatelessWidget {
  const _HowItWorksRow({
    required this.number,
    required this.title,
    this.note,
    this.last = false,
  });

  final int number;
  final String title;
  final String? note;
  final bool last;

  static const double _ring = 24;

  static const EdgeInsets noteInsets = EdgeInsets.only(top: 2, bottom: 6);

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final line = tty.dim.withValues(alpha: 0.6);
    // As tall as its words and the space under them, so the thread runs through that space to the
    // next ring.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _ring,
            child: Column(
              children: [
                Container(
                  width: _ring,
                  height: _ring,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: line),
                  ),
                  child: Text(
                    '$number',
                    style: tty.style(color: tty.faint, size: TtySize.meta),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Centred on the ring while it is one line; wraps under itself after.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _ring),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: tty.style(
                          size: TtySize.row,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (note case final note?)
                    Padding(
                      padding: noteInsets,
                      child: Text(
                        note,
                        style: tty
                            .style(color: tty.faint, size: TtySize.meta)
                            .copyWith(height: 1.45),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
