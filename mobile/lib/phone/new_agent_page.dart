import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/engine_identity.dart';
import 'package:harness/widgets/remote_folder_picker.dart';

import 'phone_header.dart';
import 'settings_row.dart';

/// Starting an agent from the phone: a folder on that machine, and an engine to
/// run there.
///
/// A page rather than a sheet. There are two choices to make and one of them can
/// open a folder browser on top — a sheet that has to be dismissed to reach the
/// browser, and rebuilt after it, loses the other choice on the way.
///
/// The desktop asks the same two things (`widgets/new_agent_dialog.dart`) and a
/// few more it has room for — a Codex profile, a split to place the pane into,
/// a permission bypass. A phone shows one agent at a time, so there is no split
/// to aim at, and the rest belong to the machine that already knows them.
class NewAgentPage extends StatefulWidget {
  const NewAgentPage({
    super.key,
    required this.notifier,
    required this.machineId,
  });

  final AppNotifier notifier;
  final String machineId;

  @override
  State<NewAgentPage> createState() => _NewAgentPageState();
}

class _NewAgentPageState extends State<NewAgentPage> {
  String? _folder;
  String? _engine;
  String? _error;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // Which engines this machine actually has. Best effort: an unanswered probe
    // leaves the list to the engines its own agents are already running, and a
    // machine with neither still gets the browse-and-create path.
    unawaited(widget.notifier.probeEngines(widget.machineId));
  }

  MachineState? get _machine => widget.notifier.stateOf(widget.machineId);

  /// The folders this machine's agents already work in, most recently seen
  /// first — on a machine with agents, the answer is nearly always one of them.
  List<AgentProject> get _knownProjects {
    final machine = _machine;
    if (machine == null) return const [];
    final byPath = <String, AgentProject>{};
    for (final agent in machine.agents) {
      final project = machine.projectOf(agent);
      if (project != null) byPath.putIfAbsent(project.cwd, () => project);
    }
    return byPath.values.toList();
  }

  /// Engines to offer: what the machine reported, else what its agents run.
  List<String> get _engines {
    final machine = _machine;
    if (machine == null) return const [];
    final reported = machine.engines.byEngine.values
        .where((entry) => entry.installed)
        .map((entry) => entry.engine);
    // An agent's engine is nullable — one whose engine the machine never named
    // has nothing to offer here.
    final running = machine.agents
        .map((agent) => agent.engine)
        .whereType<String>();
    return {...reported, ...running}.toList()..sort();
  }

  Future<void> _browse() async {
    final chosen = await showRemoteFolderPicker(
      context,
      notifier: widget.notifier,
      machineId: widget.machineId,
      initialPath: _folder,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _folder = chosen;
      _error = null;
    });
  }

  Future<void> _create() async {
    final folder = _folder, engine = _engine;
    if (folder == null || engine == null || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    final error = await widget.notifier.createAgent(
      widget.machineId,
      engine: engine,
      folder: folder,
    );
    if (!mounted) return;
    if (error == null) {
      // The new agent reaches the list behind this page on its own, the way
      // every other agent does — there is nothing here to hand it.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _creating = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final machine = _machine;
      final ready = _folder != null && _engine != null && !_creating;
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          child: Column(
            children: [
              PhoneHeader(
                title: 'New agent',
                subtitle: Text(
                  machine?.machine.displayName ?? '',
                  style: TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    const SettingsCaption('FOLDER'),
                    SettingsGroup(
                      children: [
                        for (final project in _knownProjects)
                          SettingsRow(
                            title: project.name,
                            detail: project.cwd,
                            leading: Icon(
                              LucideIcons.folder300,
                              size: 18,
                              color: AppPalette.textSecondary,
                            ),
                            trailing: _check(_folder == project.cwd),
                            onTap: () => setState(() {
                              _folder = project.cwd;
                              _error = null;
                            }),
                          ),
                        SettingsRow(
                          title: 'Browse…',
                          detail: _knownProjects.any((p) => p.cwd == _folder)
                              ? null
                              : _folder,
                          leading: Icon(
                            LucideIcons.folderSearch300,
                            size: 18,
                            color: AppPalette.textSecondary,
                          ),
                          onTap: () => unawaited(_browse()),
                        ),
                      ],
                    ),
                    const SettingsCaption('ENGINE'),
                    SettingsGroup(
                      children: [
                        for (final engine in _engines)
                          SettingsRow(
                            title: engineIdentity(engine).label,
                            leading: EngineMark(engine: engine, size: 18),
                            trailing: _check(_engine == engine),
                            onTap: () => setState(() {
                              _engine = engine;
                              _error = null;
                            }),
                          ),
                        if (_engines.isEmpty)
                          SettingsRow(
                            title: 'No engines reported',
                            detail:
                                'This machine has not answered which engines '
                                'it has. Start one agent from Harness there '
                                'and it will be offered here.',
                          ),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: AppPalette.offline,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: ready ? () => unawaited(_create()) : null,
                    child: Text(_creating ? 'Starting…' : 'Create agent'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget? _check(bool selected) => selected
      ? Icon(LucideIcons.check300, size: 18, color: AppPalette.accent)
      : null;
}
