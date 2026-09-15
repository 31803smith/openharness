import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../analytics/analytics.dart';
import '../state/pane_arrangement.dart';
import '../core/engine_availability.dart';
import '../core/codex_profiles.dart';
import '../core/project_folder.dart';
import '../core/repository_clone.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_checkbox.dart';
import '../shared/widgets/app_choice_picker.dart';
import '../shared/widgets/app_dialog.dart';
import '../shared/widgets/app_select_field.dart';
import '../shared/widgets/labeled_field.dart';
import '../state/app_state.dart';
import 'engine_identity.dart';
import 'codex_profile_field.dart';
import 'agent_picker.dart';
import 'remote_folder_picker.dart';

/// Mirrors the harness CLI's `BYPASS_PERMISSION_FLAGS`
/// (autonomous-harness/cli/src/lib/engineLaunch.ts) 1:1 — this is UI-only display + gating, the CLI
/// is the actual enforcement point. An engine absent here shows no checkbox at all rather than
/// guessing a flag for a CLI we haven't verified. Keep both maps in sync.
const Map<String, String> kEngineBypassPermissionFlag = {
  'claude': '--dangerously-skip-permissions',
  'codex': '--dangerously-bypass-approvals-and-sandbox',
  'cursor': '--force',
  'opencode': '--auto',
};

enum NewAgentDialogResult { created, findExisting, backToSearch }

enum _FolderSource { newProject, local, remote }

/// Opens the Create Agent dialog for [machineId].
///
/// [source] names the door it was opened by — `machine_row`, `rail_empty`,
/// `pane_empty` or `shortcut` — and is required rather than defaulted, so a
/// fifth entry point has to say which one it is instead of quietly filing
/// itself under an existing name.
///
/// Hosts with an Add picker can set [offerFindExisting] and handle
/// [NewAgentDialogResult.findExisting] after the dialog closes.
Future<NewAgentDialogResult?> showNewAgentDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId, {
  required String source,
  String? initialFolder,
  String? swarmId,
  PaneSplitRequest? split,
  Future<void>? initialEngineProbe,
  bool offerFindExisting = false,
  bool offerBackToSearch = false,
}) {
  // Reported here rather than at each call site: the doors are four and
  // growing, and one that forgets to track is a hole in the funnel that only
  // shows up as a number quietly being too small.
  analytics.newAgentOpened(source: source);
  return showAppDialog<NewAgentDialogResult>(
    context: context,
    transitionDuration: Duration.zero,
    veilBlur: 0,
    builder: (context) => _NewAgentDialog(
      notifier: notifier,
      machineId: machineId,
      initialFolder: initialFolder,
      swarmId: swarmId ?? notifier.activeSwarmId,
      split: split,
      initialEngineProbe: initialEngineProbe,
      offerFindExisting: offerFindExisting,
      offerBackToSearch: offerBackToSearch,
    ),
  );
}

class _NewAgentDialog extends StatefulWidget {
  final AppNotifier notifier;
  final String machineId;
  final String? initialFolder;
  final String swarmId;
  final PaneSplitRequest? split;
  final Future<void>? initialEngineProbe;
  final bool offerFindExisting;
  final bool offerBackToSearch;

  const _NewAgentDialog({
    required this.notifier,
    required this.machineId,
    this.initialFolder,
    required this.swarmId,
    this.split,
    this.initialEngineProbe,
    required this.offerFindExisting,
    required this.offerBackToSearch,
  });

  @override
  State<_NewAgentDialog> createState() => _NewAgentDialogState();
}

class _NewAgentDialogState extends State<_NewAgentDialog> {
  final _folderFocus = FocusNode(debugLabel: 'Working folder');
  final _actionFocus = FocusNode(debugLabel: 'Create or check agent');
  final _repositoryFocus = FocusNode(debugLabel: 'Repository URL');
  final _repository = TextEditingController();
  final _advancedKey = GlobalKey();
  final _choicesScroll = ScrollController();
  _FolderSource _folderSource = _FolderSource.local;
  String? _preparedFolder;
  AgentCreationAttempt? _creation;
  bool _checkingCreation = false;
  bool get _confirmationPending => _creation?.awaitingConfirmation == true;
  bool get _choicesLocked => _submitting || _confirmationPending;
  late String _engine = allEngines.first.id;
  bool _engineChosenByUser = false;
  late String _machineId = widget.machineId;
  int _machineRevision = 0;
  late String? _folder = widget.initialFolder;
  LocalCodexProfile? _codexProfile;
  bool _codexProfilesBusy = true;
  bool _bypassPermission = false;

  /// Whether the fold is open. Closed on every open of the dialog, deliberately:
  /// it is shut for the case it exists to serve, and a drawer that remembers
  /// being open is a drawer that is open for somebody who never asked.
  bool _advancedOpen = false;
  bool _machineChoicesOpen = false;
  bool _submitting = false;

  @override
  void dispose() {
    _folderFocus.dispose();
    _actionFocus.dispose();
    _repositoryFocus.dispose();
    _repository.dispose();
    _choicesScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final remembered = widget.notifier.agentPreference.value;
    if (allEngines.any((identity) => identity.id == remembered)) {
      _engine = remembered!;
      _engineChosenByUser = true;
    } else {
      _engine = _preferredInstalledEngine();
    }
    // Which engines this machine actually has. Asked here rather than at
    // connect because the answer costs the far side one interactive shell per
    // engine and is only ever read on this screen. Deferred a frame so the
    // probe's first notifyListeners() does not land mid-build.
    //
    // `force`, every time this dialog opens. A cached answer is worth nothing
    // here: engines arrive and leave through a terminal this app never sees —
    // `npm i -g opencode-ai`, `npm uninstall -g`, a venv deleted out from under
    // a symlink — and an install this very dialog started makes its own stored
    // answer stale the moment it finishes. Re-asking is bounded (one sweep, on
    // a deliberate user action) and the stored rows keep rendering until the new
    // answer lands, so nothing blanks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // The modal's fallback focus can win autofocus. Claim the first
        // actionable control once the route and its focus tree are mounted.
        _folderFocus.requestFocus();
        unawaited(_probeEngines(initialProbe: widget.initialEngineProbe));
        unawaited(_loadAgentPreference());
      }
    });
  }

  Future<void> _loadAgentPreference() async {
    await widget.notifier.agentPreference.load();
    if (!mounted || _choicesLocked || _engineChosenByUser) return;
    final remembered = widget.notifier.agentPreference.value;
    if (allEngines.any((identity) => identity.id == remembered)) {
      setState(() {
        _engineChosenByUser = true;
        if (_engine != remembered) {
          _engine = remembered!;
          _codexProfile = null;
          _codexProfilesBusy = true;
        }
      });
    }
  }

  String _preferredInstalledEngine() {
    final engines = widget.notifier.stateOf(_machineId)?.engines;
    if (engines?.loaded != true || engines?[_engine]?.installed == true) {
      return _engine;
    }
    return allEngines
            .where((identity) => engines?[identity.id]?.installed == true)
            .firstOrNull
            ?.id ??
        _engine;
  }

  Future<void> _probeEngines({Future<void>? initialProbe}) async {
    final machineId = _machineId;
    final revision = _machineRevision;
    await (initialProbe ??
        widget.notifier.probeEngines(machineId, force: true));
    if (!mounted ||
        revision != _machineRevision ||
        _choicesLocked ||
        _engineChosenByUser) {
      return;
    }
    final preferred = _preferredInstalledEngine();
    if (preferred == _engine) return;
    setState(() {
      _engine = preferred;
      _codexProfile = null;
      _codexProfilesBusy = true;
    });
  }

  /// What this machine said about the selected engine, or null while the probe
  /// is still out (or when the machine could not answer).
  ///
  /// Null is deliberately not "missing": until the machine has spoken, this
  /// dialog behaves exactly as it did before the probe existed. Claiming an
  /// engine is absent on no evidence would send someone to install one they
  /// already have.
  EngineAvailability? _availability(String engine) {
    final machine = widget.notifier.stateOf(_machineId);
    if (machine == null || !machine.engines.loaded) return null;
    return machine.engines[engine];
  }

  /// A failed availability check can be retried without changing the choices.
  bool get _engineCheckFailed {
    final machine = widget.notifier.stateOf(_machineId);
    if (machine == null) return false;
    return !machine.engines.loaded && machine.engines.error != null;
  }

  bool get _checkingEngines =>
      widget.notifier.stateOf(_machineId)?.engines.inFlight != null;

  void _retryEngineCheck() {
    if (_choicesLocked || _checkingEngines) return;
    unawaited(_probeEngines());
  }

  /// Surface a changed permission setting without repeating the default profile.
  String _advancedState() => _bypassPermission ? 'Approvals off' : '';

  bool _picking = false;
  bool _folderHovered = false;
  bool _folderFocused = false;
  bool _bypassHovered = false;
  String? _error;

  /// Whether the machine this agent will run on is the computer the app is
  /// running on, which is what decides where the folder is picked.
  ///
  /// Read per build rather than cached: `localOnly`/`localEndpoint` are settled
  /// by `_refreshMachines`, which can land while this dialog is open.
  bool get _machineIsThisComputer =>
      widget.notifier.stateOf(_machineId)?.isLocalMachine ?? false;

  /// Create waits while the Codex profile list is still loading on a machine
  /// that can launch into one, so a click cannot land before the choice does.
  bool get _waitingForCodexProfile =>
      _engine == 'codex' &&
      _availability('codex')?.supportsCodexHome == true &&
      _codexProfilesBusy;

  /// [Machine.displayName], not `name` — the latter is nullable and a machine
  /// that never got one would title the dialog "Create Agent on null".
  String get _machineName =>
      widget.notifier.stateOf(_machineId)?.machine.displayName ??
      'this machine';

  String _machineDetail(MachineState machine) => [
    machine.isLocalMachine ? 'This computer' : 'Remote',
    if (machine.nodeOnline == false)
      'Offline'
    else if (machine.needsLink)
      'Link required',
  ].join(' · ');

  Future<void> _browse() async {
    if (_picking || _choicesLocked) return;
    final restoreFocus = _folderFocus.hasFocus;
    // The agent runs on the MACHINE, so the folder has to exist on the machine
    // — which is the whole reason this branches.
    //
    // On this computer that is the OS's own panel (`getDirectoryPath` is
    // NSOpenPanel on macOS, IFileDialog on Windows, the desktop's file-chooser
    // portal on Linux): it is the picker the user already knows, it can reach
    // sidebar favourites, iCloud and network mounts that `fs_list_dir` never
    // enumerates, and the app is not sandboxed (`macos/Runner/*.entitlements`
    // declares no `com.apple.security.app-sandbox`) so the path it returns is
    // one the CLI can actually open — no security-scoped bookmark to hand over.
    //
    // On any other machine a native panel is not merely wrong but actively
    // misleading: it browses THIS Mac and hands back a path that does not exist
    // over there, so the agent would fail to start in a folder the user watched
    // themselves select. That case keeps the in-app browser, which walks the
    // remote filesystem over the `fs_list_dir` RPC.
    var acceptedFolder = false;
    setState(() => _picking = true);
    final pickingRevision = _machineRevision;
    try {
      final picked = _machineIsThisComputer
          ? await getDirectoryPath(initialDirectory: _folder)
          : await showRemoteFolderPicker(
              context,
              notifier: widget.notifier,
              machineId: _machineId,
              initialPath: _folder,
            );
      if (!mounted) return;
      setState(() {
        _picking = false;
        if (picked != null &&
            !_choicesLocked &&
            pickingRevision == _machineRevision) {
          _folder = picked;
          _error = null;
          acceptedFolder = true;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        if (pickingRevision == _machineRevision) {
          _error = 'Could not open the folder picker: $error';
        }
      });
    } finally {
      if (mounted && restoreFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_choicesLocked &&
              !_picking &&
              pickingRevision == _machineRevision) {
            // A confirmed folder makes the primary action the next step.
            // Cancellation/failure keeps Enter on browsing, and a pending
            // account choice must not focus a disabled submit button.
            if (acceptedFolder && !_waitingForCodexProfile) {
              _actionFocus.requestFocus();
            } else {
              _folderFocus.requestFocus();
            }
          }
        });
      }
    }
  }

  Future<void> _submit() async {
    final project = _preparedFolder == null ? _projectFolder : null;
    final folder =
        _preparedFolder ??
        (_folderSource == _FolderSource.local ? _folder : null);
    if ((folder == null && project == null) ||
        _submitting ||
        (!_confirmationPending && _waitingForCodexProfile)) {
      return;
    }
    final engine = _engine;
    final profile = _codexProfile;
    final bypassPermission =
        _bypassPermission && kEngineBypassPermissionFlag.containsKey(engine);
    if (!_confirmationPending) _creation = AgentCreationAttempt();
    setState(() {
      _checkingCreation = _confirmationPending;
      _submitting = true;
      _error = null;
    });
    final error = await widget.notifier.createAgent(
      _machineId,
      engine: engine,
      folder: folder ?? '',
      projectFolder: project,
      swarmId: widget.swarmId,
      split: widget.split,
      bypassPermission: bypassPermission,
      // Keep the explicit choice even if machine discovery changes mid-submit.
      // The notifier must reject a now-remote target, never use its default login.
      codexHome: engine == 'codex' ? profile?.path : null,
      attempt: _creation,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        if (!_confirmationPending) {
          _preparedFolder = _creation?.preparedFolder;
        }
        _submitting = false;
        _error = error;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _actionFocus.requestFocus();
      });
      return;
    }
    analytics.agentCreated(engine: engine, bypassPermission: bypassPermission);
    Navigator.of(context).pop(NewAgentDialogResult.created);
  }

  ProjectFolderRequest? get _projectFolder => switch (_folderSource) {
    _FolderSource.newProject => const ProjectFolderRequest.newProject(),
    _FolderSource.local => null,
    _FolderSource.remote => switch (GitHubRepository.parse(_repository.text)) {
      final repository? => ProjectFolderRequest.remote(repository),
      null => null,
    },
  };

  void _selectFolderSource(_FolderSource source) {
    if (_folderSource == source || _choicesLocked || _picking) return;
    setState(() {
      _folderSource = source;
      _preparedFolder = null;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (source) {
        case _FolderSource.local:
          _folderFocus.requestFocus();
        case _FolderSource.remote:
          _repositoryFocus.requestFocus();
        case _FolderSource.newProject:
          if (!_waitingForCodexProfile) _actionFocus.requestFocus();
      }
    });
  }

  void _toggleAdvanced() {
    setState(() => _advancedOpen = !_advancedOpen);
    if (!_advancedOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_advancedOpen) return;
      final anchor = _advancedKey.currentContext;
      if (anchor == null) return;
      unawaited(
        Scrollable.ensureVisible(
          anchor,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reads colour tokens, and lives in an Overlay — a top-down rebuild never
    // reaches it, so it has to watch for itself or it strands on the palette it
    // opened with.
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) => PopScope(
        // The launch request cannot be cancelled after it is sent. Keep its
        // outcome visible instead of allowing an accidental second launch.
        canPop: !_submitting,
        child: _buildDialog(context),
      ),
    );
  }

  Widget _buildDialog(BuildContext context) {
    final bypassFlag = kEngineBypassPermissionFlag[_engine];
    final canCreate =
        (_preparedFolder != null ||
            (_folderSource == _FolderSource.local
                ? _folder != null
                : _projectFolder != null)) &&
        !_picking &&
        !_submitting &&
        (_confirmationPending || !_waitingForCodexProfile);

    return AlertDialog(
      title: Text(switch (widget.split?.axis) {
        PaneResizeAxis.x => 'New Agent to the right',
        PaneResizeAxis.y => 'New Agent below',
        null => 'New Agent',
      }),
      titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: grid.AppFont.semibold,
        color: grid.AppPalette.textPrimary,
      ),
      titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      actionsPadding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      actionsOverflowButtonSpacing: 8,
      content: SizedBox(
        width: _dialogWidth,
        child: Scrollbar(
          controller: _choicesScroll,
          thumbVisibility: true,
          thickness: 4,
          radius: const Radius.circular(2),
          child: SingleChildScrollView(
            controller: _choicesScroll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AbsorbPointer(
                  absorbing: _choicesLocked,
                  child: ExcludeFocus(
                    excluding: _choicesLocked,
                    child: _choices(bypassFlag),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: _gapBlock),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _confirmationPending
                            ? grid.AppPalette.textSecondary
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!_confirmationPending && !widget.offerBackToSearch)
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: grid.AppPalette.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
        if (_confirmationPending || widget.offerBackToSearch)
          TextButton(
            onPressed: _submitting
                ? null
                : () => Navigator.of(context).pop(
                    widget.offerBackToSearch && !_confirmationPending
                        ? NewAgentDialogResult.backToSearch
                        : null,
                  ),
            style: TextButton.styleFrom(
              foregroundColor: grid.AppPalette.textSecondary,
            ),
            child: Text(_confirmationPending ? 'Close' : 'Back to Search'),
          ),
        if (widget.offerFindExisting &&
            _confirmationPending &&
            (!_submitting || _checkingCreation))
          TextButton.icon(
            onPressed: _submitting
                ? null
                : () =>
                      Navigator.of(context)
                          .pop(NewAgentDialogResult.findExisting),
            icon: const Icon(LucideIcons.search, size: 16),
            label: const Text('Find an agent'),
          ),
        FilledButton(
          key: const ValueKey('create-agent-submit'),
          focusNode: _actionFocus,
          onPressed: canCreate ? _submit : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(136, 42),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            backgroundColor: grid.AppPalette.swarmAccent,
            foregroundColor: grid.AppPalette.swarmTabBar,
            shape: const StadiumBorder(),
            disabledForegroundColor: _submitting
                ? grid.AppPalette.textPrimary
                : null,
          ),
          child: _submitting
              ? Semantics(
                  liveRegion: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _checkingCreation
                            ? 'Checking status…'
                            : _folderSource == _FolderSource.remote &&
                                  _preparedFolder == null
                            ? 'Cloning and starting…'
                            : 'Creating agent…',
                      ),
                    ],
                  ),
                )
              : Text(_confirmationPending ? 'Check status' : 'Create Agent'),
        ),
      ],
    );
  }

  Widget _choices(String? bypassFlag) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Agent'),
        AgentPicker(
          compact: true,
          value: _engine,
          options: [
            for (final identity in allEngines)
              SelectOption(
                value: identity.id,
                label: identity.label,
                leading: () => EngineMark(engine: identity.id, size: 14),
              ),
          ],
          onChanged: (value) => setState(() {
            unawaited(widget.notifier.agentPreference.select(value));
            _engineChosenByUser = true;
            _engine = value;
            _error = null;
            _codexProfile = null;
            _codexProfilesBusy = true;
            if (!kEngineBypassPermissionFlag.containsKey(value)) {
              _bypassPermission = false;
            }
          }),
        ),
        if (!_confirmationPending && _engineCheckFailed) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Couldn’t check whether ${engineIdentity(_engine).label} is installed. '
                  'You can still try creating an agent.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: grid.AppPalette.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                key: const Key('new-agent-retry-check'),
                onPressed: _checkingEngines ? null : _retryEngineCheck,
                child: Text(_checkingEngines ? 'Checking…' : 'Retry'),
              ),
            ],
          ),
        ],
        const SizedBox(height: _gapField),
        _projectHeader(),
        const SizedBox(height: 10),
        if (_folderSource == _FolderSource.local)
          _FolderControl(
            folder: _folder,
            machineName: _machineName,
            machineIsThisComputer: _machineIsThisComputer,
            picking: _picking,
            focusNode: _folderFocus,
            hovered: _folderHovered,
            focused: _folderFocused,
            onHover: (value) => setState(() => _folderHovered = value),
            onFocusChange: (value) => setState(() => _folderFocused = value),
            onPressed: _browse,
          ),
        if (_folderSource == _FolderSource.newProject)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Creates a new folder in ~/harnesses.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: grid.AppPalette.textSecondary),
              ),
            ),
          ),
        if (_folderSource == _FolderSource.remote) ...[
          TextField(
            key: const ValueKey('new-agent-repository'),
            controller: _repository,
            focusNode: _repositoryFocus,
            decoration: InputDecoration(
              hintText: 'GitHub URL or owner/repository',
              filled: true,
              fillColor: grid.AppSurface.recess,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(grid.AppControl.radius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(grid.AppControl.radius),
                borderSide: BorderSide(color: grid.AppPalette.accentOnSurface),
              ),
            ),
            onChanged: (_) => setState(() {
              _preparedFolder = null;
              _error = null;
            }),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          Text(
            'Clone into ~/harnesses on $_machineName.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: grid.AppPalette.textSecondary),
          ),
        ],
        const SizedBox(height: _gapField),
        _machineSelector(),
        // Profiles keep loading while collapsed; creation still waits for them.
        const SizedBox(height: _gapBlock),
        _Advanced(
          key: _advancedKey,
          open: _advancedOpen,
          state: _advancedState(),
          onToggle: _toggleAdvanced,
          children: [
            if (_engineCheckFailed) ...[
              Text(
                'If $_machineName uses an older Harness CLI, update it to enable engine checks.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: grid.AppPalette.textSecondary),
              ),
              const SizedBox(height: 10),
            ],
            if (_engine == 'codex') ...[
              if (_availability('codex')?.supportsCodexHome == true)
                CodexProfileField(
                  notifier: widget.notifier,
                  machineId: _machineId,
                  machineIsThisComputer: _machineIsThisComputer,
                  value: _codexProfile,
                  observedPaths: {
                    for (final agent
                        in widget.notifier.stateOf(_machineId)!.agents)
                      if (agent.engine == 'codex' && agent.codexHome != null)
                        agent.codexHome!,
                  },
                  onChanged: (profile) {
                    if (!_choicesLocked) {
                      setState(() => _codexProfile = profile);
                    }
                  },
                  onBusyChanged: (busy) {
                    if (_codexProfilesBusy != busy) {
                      setState(() => _codexProfilesBusy = busy);
                    }
                  },
                )
              else
                Text(
                  _availability('codex') == null
                      ? _engineCheckFailed && !_checkingEngines
                            ? 'Retry the agent check above to load Codex profiles.'
                            : 'Checking whether $_machineName supports Codex profiles…'
                      : 'Update Harness CLI on $_machineName to choose a Codex profile.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (_engine == 'codex') ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: grid.AppGlass.hair),
              const SizedBox(height: 16),
            ],
            const FieldLabel('Permissions'),
            if (bypassFlag != null)
              _BypassCheck(
                value: _bypassPermission,
                flag: bypassFlag,
                hovered: _bypassHovered,
                onHover: (value) => setState(() => _bypassHovered = value),
                onChanged: (value) => setState(() => _bypassPermission = value),
              )
            else
              // Not silence: an engine with no checkbox looks identical to one whose
              // checkbox the user simply missed.
              Text(
                'Managed by ${engineIdentity(_engine).label}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }

  Widget _projectHeader() => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      children: [
        Text(
          'Project',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: grid.AppPalette.textSecondary),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: grid.AppSurface.recess,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (source, label) in [
                  (_FolderSource.newProject, 'New'),
                  (_FolderSource.local, 'Local'),
                  (_FolderSource.remote, 'Remote'),
                ])
                  Semantics(
                    selected: _folderSource == source,
                    inMutuallyExclusiveGroup: true,
                    child: TextButton(
                      key: ValueKey('new-agent-folder-${source.name}'),
                      onPressed: () => _selectFolderSource(source),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(60, 30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        foregroundColor: _folderSource == source
                            ? grid.AppPalette.textPrimary
                            : grid.AppPalette.textSecondary,
                        backgroundColor: _folderSource == source
                            ? grid.AppSurface.recessHover
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: Text(label),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _machineSelector() {
    final machine = widget.notifier.stateOf(_machineId);
    final status = machine?.nodeOnline == false
        ? 'Offline'
        : machine?.needsLink == true
        ? 'Link required'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Run on',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: grid.AppPalette.textSecondary),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Tooltip(
                message: 'Choose machine',
                child: TextButton(
                  key: const Key('new-agent-machine-toggle'),
                  onPressed: () => setState(
                    () => _machineChoicesOpen = !_machineChoicesOpen,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: grid.AppPalette.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _machineIsThisComputer
                            ? LucideIcons.laptop
                            : LucideIcons.monitor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _machineName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          status,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: grid.AppPalette.textSecondary),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(
                        _machineChoicesOpen
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_machineChoicesOpen) ...[
          const SizedBox(height: 8),
          _machineOptions(),
        ],
      ],
    );
  }

  Widget _machineOptions() => AppChoicePicker<String>(
    key: const Key('new-agent-machine-field'),
    value: _machineId,
    moreKey: const Key('new-agent-machine-more'),
    moreLabel: 'More machines',
    optionKey: (id) => ValueKey('new-agent-machine-$id'),
    showDetails: true,
    compact: true,
    wrap: false,
    preferredValues: [
      for (final machine in widget.notifier.machineStates.values)
        if (machine.isLocalMachine) machine.machine.machineId,
    ],
    options: [
      for (final machine in widget.notifier.machineStates.values)
        SelectOption(
          value: machine.machine.machineId,
          label: machine.machine.displayName,
          detail: _machineDetail(machine),
          leading: () => Icon(
            machine.isLocalMachine ? LucideIcons.laptop : LucideIcons.monitor,
            size: 18,
          ),
        ),
    ],
    onChanged: (id) {
      if (id == _machineId || _choicesLocked) return;
      setState(() {
        _machineRevision++;
        _machineId = id;
        _folder = null;
        _preparedFolder = null;
        _codexProfile = null;
        _codexProfilesBusy = true;
        _error = null;
      });
      unawaited(_probeEngines());
    },
  );
}

/// A focused creation form; machine details expand only when requested.
const double _dialogWidth = 600;

/// A path shortened from its HEAD, so the leaf survives.
///
/// `/Users/macbookpro/Desktop/A` truncated the ordinary way keeps the part
/// every path on the machine shares and drops the only part that identifies it.
/// This drops whole leading segments instead and marks the cut with `…/`, the
/// same shorthand a shell prompt uses:
///
/// ```
/// /Users/macbookpro/work/harness/autonomous-harness-desktop
/// …/harness/autonomous-harness-desktop
/// ```
///
/// Segment-wise rather than character-wise: cutting mid-name reads as a typo,
/// while a dropped segment reads as a path someone abbreviated. Windows paths
/// come back untouched — they are separated by `\`, and a wrong guess about the
/// separator would mangle the string rather than shorten it.
/// The advance of one character at the 12pt mono the path control sets — the
/// face is 0.6em wide, like every monospaced face in this family.
///
/// Arithmetic rather than a `TextPainter`: this runs on every rebuild, and a
/// layout pass to answer a question this cheap is a poor trade.
const double _monoAdvance = 12 * 0.6;

String _ellipsizeHead(String path, double maxWidth) {
  final fits = path.length * _monoAdvance <= maxWidth;
  if (fits || !path.contains('/')) return path;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  // Never below the leaf: a control too narrow for even that shows the leaf and
  // lets the Text's own ellipsis take the rest.
  for (var drop = 1; drop < segments.length; drop++) {
    final candidate = '…/${segments.skip(drop).join('/')}';
    if (candidate.length * _monoAdvance <= maxWidth) return candidate;
  }
  return '…/${segments.last}';
}

/// A path or a flag, in the face the user chose for code.
///
/// Built from [grid.AppFont] rather than a literal family so it follows Settings
/// ▸ Terminal, and carries `monoFallback` — without it a user whose chosen face
/// lacks a glyph gets Roboto for that one character.
///
/// One size for every mono string here, taken off the ramp rather than picked
/// per call: the path, the flag under the checkbox and the flag in the command
/// are the same kind of text, and three hand-set sizes is how they stop looking
/// like it. `labelSmall`'s 12 is a step under the 13 of the controls around
/// them, which is where a monospaced face has to sit to read at the same size.
TextStyle _mono({required Color color}) => TextStyle(
  fontFamily: grid.AppFont.mono,
  fontFamilyFallback: grid.AppFont.monoFallback,
  fontSize: 12,
  color: color,
);

// The dialog's spacing scale. Four steps, named, rather than the run of
// 3/6/7/8/10/12/14/16/18 this file grew — a column whose gaps are all slightly
// different is what "the padding feels off" actually is.
//
// `FieldLabel` already carries its own 6px gap to the control it names, so a
// caption never takes a step from here; these are the gaps BETWEEN things.

/// A label and the line it belongs to — the flag under its title.
const double _gapTight = 4;

/// Blocks inside one card: the command, the facts, the reason.
const double _gapBlock = 12;

/// One field and the next, down the choices column.
const double _gapField = 24;

/// The folder control: one target, not a text box with a button beside it.
///
/// The old shape put a read-only `InputDecorator` next to a `Browse…` button,
/// which read as a field you could type in and as the loudest control in the
/// dialog. Here the whole row is the button — the path is what it displays, and
/// the trailing word says what clicking does.
/// The fold that holds what most people never touch.
///
/// A ROW THAT REPORTS ITSELF. Everything about this is ordinary — a twisty, a
/// label, some children — except the state printed on the right, and that is the
/// part doing the work. Two settings were moved out of sight here; a drawer that
/// hides what it is set to is one people open every time to check, which costs
/// more than leaving the controls where they were.
///
/// AMBER, NOT RED, when the prompts are off. Red on this desktop means destroy,
/// and it was tried: a red "Create without prompts" button read as though the
/// button itself were dangerous rather than the setting behind it. Amber is
/// already what this app gives that flag wherever else it appears.
class _Advanced extends StatelessWidget {
  const _Advanced({
    super.key,
    required this.open,
    required this.state,
    required this.onToggle,
    required this.children,
  });

  final bool open;

  /// What is set, in a few words — see `_advancedState`. Empty says nothing.
  final String state;

  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const Key('new-agent-advanced'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                // Rotated rather than swapped for a second glyph: one shape
                // turning reads as the same control in two positions, which is
                // what it is.
                AnimatedRotation(
                  turns: open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: grid.AppPalette.textFaint,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Advanced',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: grid.AppPalette.textSecondary,
                  ),
                ),
                const Spacer(),
                if (!open)
                  Flexible(
                    child: Text(
                      key: const Key('new-agent-advanced-state'),
                      state,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: grid.AppPalette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // HIDDEN, NOT UNMOUNTED, and that is not a preference — it is what the
        // dialog needs to work at all.
        //
        // It was `if (open)` first, on the reasoning that a shut drawer should
        // not pay for a question nobody asked. The Codex profile field is the
        // thing that asks the machine for its profiles, and TWO things downstream
        // depend on its having asked: it clears `_codexProfilesBusy`, which gates
        // the Create button, and it auto-selects when there is exactly one
        // profile. Unmounted, neither ever happens — so Create stayed disabled
        // forever on Codex, with nothing on screen saying why.
        //
        // Offstage builds and runs it, and merely declines to paint it.
        Offstage(
          offstage: !open,
          child: ExcludeFocus(
            excluding: !open,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: grid.AppSurface.hoverFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderControl extends StatelessWidget {
  const _FolderControl({
    required this.folder,
    required this.machineName,
    required this.machineIsThisComputer,
    required this.picking,
    required this.focusNode,
    required this.hovered,
    required this.focused,
    required this.onHover,
    required this.onFocusChange,
    required this.onPressed,
  });

  final String? folder;
  final String machineName;
  final bool machineIsThisComputer;
  final bool picking;
  final FocusNode focusNode;
  final bool hovered;
  final bool focused;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    final chosen = folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: picking
              ? SystemMouseCursors.progress
              : SystemMouseCursors.click,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: InkWell(
            key: const Key('new-agent-folder'),
            focusNode: focusNode,
            onTap: picking ? null : onPressed,
            canRequestFocus: !picking,
            onFocusChange: onFocusChange,
            splashFactory: NoSplash.splashFactory,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            borderRadius: BorderRadius.circular(grid.AppControl.radius),
            child: AnimatedContainer(
              duration: grid.AppMotion.hover,
              curve: grid.AppMotion.curve,
              constraints: BoxConstraints(
                minHeight: grid.AppControl.heightFieldScaled.clamp(
                  52.0,
                  double.infinity,
                ),
              ),
              // The select field's own padding, so the two controls stacked in
              // this column share one left edge and one right edge.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (hovered || focused) && !picking
                    ? grid.AppSurface.recessHover
                    : grid.AppSurface.recess,
                borderRadius: BorderRadius.circular(grid.AppControl.radius),
                border: Border.all(
                  color: focused
                      ? grid.AppPalette.accentOnSurface
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 20,
                    color: grid.AppPalette.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    key: const Key('new-agent-folder-text'),
                    // Aligned left like every other control's content.
                    //
                    // This used to set `TextDirection.rtl` to make a long path
                    // ellipsize from its head, keeping the leaf visible. But
                    // direction drives ALIGNMENT too, so the whole string was
                    // shoved to the trailing edge and left a hole after the
                    // folder glyph — wider the shorter the path, which is why a
                    // remote `/home/node/work` looked worst of all.
                    //
                    // Truncation is a job for the string, not the layout, so the
                    // head is now trimmed in [_ellipsizeHead] and the Text stays
                    // plain LTR.
                    child: LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          picking
                              ? 'Waiting for the folder picker…'
                              // Not "on $machineName": the title says which
                              // machine and so does the summary, and a hostname
                              // like `MacBooks-MacBook-Pro.local` spent the
                              // whole control repeating it, then truncated.
                              : chosen == null
                              ? 'Choose a folder…'
                              : _ellipsizeHead(chosen, constraints.maxWidth),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: chosen != null && !picking
                              ? _mono(color: grid.AppPalette.textPrimary)
                              : theme.textTheme.labelMedium?.copyWith(
                                  color: grid.AppPalette.textSecondary,
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (!picking) ...[
                    const SizedBox(width: 8),
                    Text(
                      chosen == null ? 'Browse…' : 'Change',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: grid.AppPalette.accentOnSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Only the case that needs explaining gets a line. On this computer the
        // OS panel is what everyone expects and saying so is noise; on another
        // machine the in-app browser is the surprising half, so that is the half
        // that speaks.
        if (!machineIsThisComputer) ...[
          const SizedBox(height: _gapTight),
          Text(
            'Choose a folder on $machineName.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// The bypass checkbox, in the app's own row shape.
///
/// Not `CheckboxListTile`: that was the only Material list tile left in the app,
/// and its `dense`/`contentPadding` combination left the box floating well clear
/// of the text it labels and out of line with the fields above it.
class _BypassCheck extends StatelessWidget {
  const _BypassCheck({
    required this.value,
    required this.flag,
    required this.hovered,
    required this.onHover,
    required this.onChanged,
  });

  final bool value;
  final String flag;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          // Bled out to the left so the row's fill lines up with the fields
          // above it, and the text still starts on their left edge once the
          // box and its gap are counted.
          // NO SIDE PADDING. Ten pixels of it pushed the box in from the
          // margin every other control on this dialog starts at, so the one row
          // that is not a labelled field was also the one row that did not line
          // up with them. The hover fill simply spans the row instead.
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: hovered ? grid.AppSurface.hoverFill : Colors.transparent,
            borderRadius: BorderRadius.circular(grid.AppControl.radius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nudged down onto the label's own line: the row is top-aligned
              // so the two-line block reads from its title, and a 16px box
              // centred on a 13pt cap sits a hair proud of it.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AppCheckbox(
                  value: value,
                  hovered: hovered,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Bypass permission prompts',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: grid.AppPalette.textPrimary,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: flag,
                          child: Icon(
                            LucideIcons.info,
                            size: 14,
                            color: grid.AppPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _gapTight),
                    Text(
                      'Allow this agent to act without asking for approval.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: grid.AppPalette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
