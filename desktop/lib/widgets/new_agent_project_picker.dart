import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/repository_clone.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_choice_picker.dart';
import '../shared/widgets/app_dialog.dart';
import '../shared/widgets/app_select_field.dart';
import '../state/app_state.dart';

class NewAgentProjectPicker extends StatefulWidget {
  const NewAgentProjectPicker({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.focusNode,
    required this.tileSize,
    required this.onSelected,
    required this.onBrowse,
    this.initialFolder,
    this.locked = false,
  });
  final AppNotifier notifier;
  final String machineId;
  final String? initialFolder;
  final FocusNode focusNode;
  final Size tileSize;
  final bool locked;
  final void Function(String? folder, GitHubRepository? repository) onSelected;
  final Future<String?> Function() onBrowse;

  @override
  State<NewAgentProjectPicker> createState() => _NewAgentProjectPickerState();
}

enum _ProjectSource { newProject, local, git, recent }

typedef _ProjectChoice = ({
  _ProjectSource source,
  String? folder,
  GitHubRepository? repository,
});

class _NewAgentProjectPickerState extends State<NewAgentProjectPicker> {
  late _ProjectSource _source = widget.initialFolder == null
      ? _ProjectSource.newProject
      : _ProjectSource.local;
  late String? _folder = widget.initialFolder;
  GitHubRepository? _repository;
  bool _chosen = false, _browsing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void didUpdateWidget(covariant NewAgentProjectPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A failed launch may have prepared a folder already. Retrying uses it.
    if (widget.initialFolder != oldWidget.initialFolder &&
        widget.initialFolder != null &&
        widget.initialFolder != _folder) {
      _folder = widget.initialFolder;
      _repository = null;
      _source = _ProjectSource.local;
      _rememberChoice();
    }
  }

  Future<void> _restore() async {
    final history = widget.notifier.projectHistory;
    await history.load();
    if (!mounted || widget.locked || _chosen || widget.initialFolder != null) {
      return;
    }
    // The dialog owns this bucket. Choices survive machine switches, never a
    // new dialog or app launch. History only supplies the Recent menu.
    final choice = PageStorage.maybeOf(context)
        ?.readState(context, identifier: ('project-choice', widget.machineId));
    if (choice is _ProjectChoice) {
      setState(() {
        _folder = choice.folder;
        _repository = choice.repository;
        _source = choice.source;
      });
      widget.onSelected(choice.folder, choice.repository);
    } else {
      setState(() {});
    }
  }

  void _rememberChoice() => PageStorage.maybeOf(context)?.writeState(
    context,
    (source: _source, folder: _folder, repository: _repository),
    identifier: ('project-choice', widget.machineId),
  );

  List<SelectOption<String>> get _recent {
    final machine = widget.notifier.stateOf(widget.machineId);
    final projects = <String, String>{};
    for (final path in widget.notifier.projectHistory.recent(
      widget.machineId,
    )) {
      projects[path] = p.basename(path);
    }
    for (final agent in machine?.agents.reversed ?? const <Agent>[]) {
      final project = machine?.projectOf(agent);
      if (project != null) {
        projects.putIfAbsent(project.cwd, () => project.name);
      }
    }
    if (_folder != null) {
      projects.putIfAbsent(_folder!, () => p.basename(_folder!));
    }
    return [
      for (final entry in projects.entries)
        SelectOption(
          value: entry.key,
          label: entry.value,
          detail: entry.key,
          leading: () => const Icon(LucideIcons.folder, size: 18),
        ),
    ];
  }

  void _select(
    _ProjectSource source, {
    String? folder,
    GitHubRepository? repository,
  }) {
    if (widget.locked) return;
    _chosen = true;
    setState(() {
      _source = source;
      _folder = folder;
      _repository = repository;
    });
    _rememberChoice();
    widget.onSelected(folder, repository);
    if (repository == null) {
      unawaited(
        widget.notifier.projectHistory.select(widget.machineId, folder),
      );
    }
  }

  Future<void> _browse() async {
    if (_browsing || widget.locked) return;
    _chosen = true;
    setState(() => _browsing = true);
    try {
      final path = await widget.onBrowse();
      if (mounted && path != null && !widget.locked) {
        _select(_ProjectSource.local, folder: path);
      }
    } finally {
      if (mounted) setState(() => _browsing = false);
    }
  }

  Future<void> _git() async {
    if (widget.locked) return;
    _chosen = true;
    final repository = await showAppDialog<GitHubRepository>(
      context: context,
      builder: (_) => _GitProjectDialog(initialUrl: _repository?.url),
    );
    if (mounted && repository != null && !widget.locked) {
      _select(_ProjectSource.git, repository: repository);
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final recent = _recent;
    final selectedRecent = _source == _ProjectSource.recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppChoiceTile(
              key: const Key('new-agent-folder-newProject'),
              size: widget.tileSize,
              focusNode: widget.focusNode,
              label: 'New project',
              leading: const Icon(LucideIcons.folderPlus, size: 18),
              selected: _source == _ProjectSource.newProject,
              onPressed: widget.locked
                  ? null
                  : () => _select(_ProjectSource.newProject),
            ),
            AppChoiceTile(
              key: const Key('new-agent-project-browse'),
              size: widget.tileSize,
              label: 'Local',
              detail: _source == _ProjectSource.local && _folder != null
                  ? p.basename(_folder!)
                  : null,
              leading: const Icon(LucideIcons.folderOpen, size: 18),
              selected: _source == _ProjectSource.local,
              onPressed: widget.locked || _browsing ? null : _browse,
            ),
            AppChoiceTile(
              key: const Key('new-agent-project-git'),
              size: widget.tileSize,
              label: 'Git',
              detail: _repository?.name,
              leading: const Icon(LucideIcons.gitBranch, size: 18),
              selected: _source == _ProjectSource.git,
              onPressed: widget.locked ? null : _git,
            ),
            Semantics(
              selected: selectedRecent,
              inMutuallyExclusiveGroup: true,
              child: AppSelectField<String>(
                key: const Key('new-agent-project-recent'),
                value: selectedRecent ? _folder ?? '' : '',
                options: recent,
                width: widget.tileSize.width,
                height: widget.tileSize.height,
                selected: selectedRecent,
                fillColor: selectedRecent
                    ? grid.AppPalette.swarmAccent.withValues(alpha: .16)
                    : grid.AppSurface.recess,
                emptyLabel: 'No recent projects',
                onChanged: (path) =>
                    _select(_ProjectSource.recent, folder: path),
                trigger: AppChoiceTileContent(
                  label: 'Recent',
                  detail: selectedRecent && _folder != null
                      ? p.basename(_folder!)
                      : null,
                  leading: const Icon(LucideIcons.history, size: 18),
                  trailing: const Icon(Icons.keyboard_arrow_down, size: 18),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GitProjectDialog extends StatefulWidget {
  const _GitProjectDialog({this.initialUrl});
  final String? initialUrl;
  @override
  State<_GitProjectDialog> createState() => _GitProjectDialogState();
}

class _GitProjectDialogState extends State<_GitProjectDialog> {
  late final _url = TextEditingController(text: widget.initialUrl);
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _select() {
    final repository = GitHubRepository.parse(_url.text);
    if (repository == null) {
      setState(() => _error = 'Enter a GitHub URL or owner/repository.');
    } else {
      Navigator.of(context).pop(repository);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _select,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _select,
    },
    child: AlertDialog(
      title: const Text('Git repository'),
      content: SizedBox(
        width: 480,
        child: TextField(
          key: const Key('new-agent-git-url'),
          controller: _url,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Paste a GitHub URL',
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _select(),
        ),
      ),
      actions: [FilledButton(onPressed: _select, child: const Text('Select'))],
    ),
  );
}
