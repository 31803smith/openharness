import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../core/repository_clone.dart';
import '../core/models.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';

class NewAgentProjectPicker extends StatefulWidget {
  const NewAgentProjectPicker({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.focusNode,
    required this.onSelected,
    required this.onBrowse,
    this.onCreate,
    this.initialFolder,
    this.locked = false,
  });
  final AppNotifier notifier;
  final String machineId;
  final String? initialFolder;
  final FocusNode focusNode;
  final bool locked;
  final VoidCallback? onCreate;
  final void Function(String? folder, GitHubRepository? repository) onSelected;
  final Future<String?> Function() onBrowse;

  @override
  State<NewAgentProjectPicker> createState() => _NewAgentProjectPickerState();
}

class _ProjectRow {
  const _ProjectRow(this.name, {this.path, this.repository});
  final String name;
  final String? path;
  final GitHubRepository? repository;
  bool get isNew => path == null && repository == null;
}

class _NewAgentProjectPickerState extends State<NewAgentProjectPicker> {
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search projects');
  final _listScroll = ScrollController();
  final _cache = <String, Map<String, dynamic>>{};
  late _ProjectRow _selection = widget.initialFolder == null
      ? const _ProjectRow('New project')
      : _ProjectRow(
          p.basename(widget.initialFolder!),
          path: widget.initialFolder,
        );
  bool _open = false, _chosen = false, _browsing = false;
  int _index = 0, _previewRevision = 0;
  Timer? _debounce;
  Map<String, dynamic>? _preview;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void didUpdateWidget(covariant NewAgentProjectPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFolder != oldWidget.initialFolder &&
        widget.initialFolder != null &&
        widget.initialFolder != _selection.path) {
      _selection = _ProjectRow(
        p.basename(widget.initialFolder!),
        path: widget.initialFolder,
      );
    }
  }

  Future<void> _restore() async {
    final history = widget.notifier.projectHistory;
    await history.load();
    if (!mounted || widget.locked || _chosen || widget.initialFolder != null) {
      return;
    }
    final path = history.selected(widget.machineId);
    if (path != null) {
      setState(() => _selection = _ProjectRow(p.basename(path), path: path));
      widget.onSelected(path, null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _previewRevision++;
    _debounce?.cancel();
    _query.dispose();
    _searchFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  List<_ProjectRow> get _rows {
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
    if (_selection.path != null) {
      projects.putIfAbsent(_selection.path!, () => _selection.name);
    }
    final query = _query.text.trim();
    final repository = query.isEmpty ? null : GitHubRepository.parse(query);
    final terms = query.toLowerCase().split(RegExp(r'\s+'));
    return [
      const _ProjectRow('New project'),
      if (repository != null)
        _ProjectRow(repository.name, repository: repository),
      for (final entry in projects.entries)
        if (query.isEmpty ||
            terms.every(
              (term) =>
                  '${entry.value} ${entry.key}'.toLowerCase().contains(term),
            ))
          _ProjectRow(entry.value, path: entry.key),
    ];
  }

  void _openSearch() {
    if (widget.locked) return;
    _chosen = true;
    _query.text = _selection.repository?.url ?? '';
    final index = _rows.indexWhere(
      (row) =>
          row.path == _selection.path &&
          row.repository?.url == _selection.repository?.url,
    );
    setState(() {
      _open = true;
      _index = math.max(0, index);
    });
    _loadPreview();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() => _open = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  void _select(_ProjectRow row) {
    if (widget.locked) return;
    _chosen = true;
    setState(() {
      _selection = row;
      _open = false;
    });
    widget.onSelected(row.path, row.repository);
    if (row.repository == null) {
      unawaited(
        widget.notifier.projectHistory.select(widget.machineId, row.path),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  bool get _hasSearchMatch => _query.text.trim().isEmpty || _rows.length > 1;

  void _confirm({bool create = false}) {
    if (!_hasSearchMatch || widget.locked) return;
    _select(_rows[_index]);
    if (create) widget.onCreate?.call();
  }

  void _highlight(int index) {
    final next = index.clamp(0, _rows.length - 1);
    if (_index == next) return;
    setState(() => _index = next);
    _loadPreview();
    if (_listScroll.hasClients) {
      final offset = math.max(0, _index - 1) * _rowHeight;
      final bottom =
          offset + _rowHeight - _listScroll.position.viewportDimension;
      if (offset < _listScroll.offset) {
        _listScroll.jumpTo(offset);
      } else if (bottom > _listScroll.offset) {
        _listScroll.jumpTo(
          bottom.clamp(0, _listScroll.position.maxScrollExtent),
        );
      }
    }
  }

  double get _rowHeight =>
      math.max(62, MediaQuery.textScalerOf(context).scale(13) * 3.6);

  void _loadPreview() {
    _debounce?.cancel();
    final revision = ++_previewRevision;
    final rows = _rows;
    final row = rows[_index.clamp(0, rows.length - 1)];
    _preview = row.path == null ? null : _cache[row.path];
    if (row.path == null || _preview != null) return;
    _debounce = Timer(const Duration(milliseconds: 160), () async {
      final result = await widget.notifier.readProjectPreview(
        widget.machineId,
        row.path!,
      );
      if (!mounted || revision != _previewRevision) return;
      if (_cache.length >= 24) _cache.remove(_cache.keys.first);
      _cache[row.path!] = result;
      setState(() => _preview = result);
    });
  }

  Future<void> _browse() async {
    if (_browsing || widget.locked) return;
    setState(() => _browsing = true);
    try {
      final path = await widget.onBrowse();
      if (mounted && path != null && !widget.locked) {
        _select(_ProjectRow(p.basename(path), path: path));
      }
    } finally {
      if (mounted) setState(() => _browsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    _index = _index.clamp(0, rows.length - 1);
    return Material(
      color: grid.AppPalette.swarmSearchSurface,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_open)
            Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    (HardwareKeyboard.instance.isMetaPressed ||
                        HardwareKeyboard.instance.isControlPressed)) {
                  _confirm(create: true);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _highlight(
                    _index +
                        (event.logicalKey == LogicalKeyboardKey.arrowDown
                            ? 1
                            : -1),
                  );
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _closeSearch();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const Key('new-agent-project-search'),
                controller: _query,
                style: const TextStyle(fontSize: 16),
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  hintText: 'Search projects or paste a Git URL',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: true,
                  fillColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Icon(LucideIcons.search, size: 20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  suffixIcon: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: grid.AppPalette.textSecondary,
                    ),
                    onPressed: _closeSearch,
                    child: const Text('esc'),
                  ),
                ),
                onChanged: (_) {
                  setState(() => _index = _rows.length > 1 ? 1 : 0);
                  _loadPreview();
                },
                onSubmitted: (_) => _confirm(),
              ),
            )
          else
            InkWell(
              key: const Key('new-agent-project-bar'),
              focusNode: widget.focusNode,
              onTap: widget.locked ? null : _openSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    Icon(
                      _selection.isNew
                          ? LucideIcons.folderPlus
                          : _selection.repository != null
                          ? LucideIcons.gitBranch
                          : LucideIcons.folder,
                      size: 21,
                      color: grid.AppPalette.textSecondary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selection.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_selection.path != null)
                            Text(
                              _selection.path!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: grid.AppPalette.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      LucideIcons.search,
                      size: 18,
                      color: grid.AppPalette.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          if (_open)
            LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >=
                    640 *
                        math.min(
                          1.3,
                          MediaQuery.textScalerOf(context).scale(14) / 14,
                        );
                Widget projectRow(int index) {
                  final row = rows[index];
                  return MouseRegion(
                    onEnter: (_) => _highlight(index),
                    child: Semantics(
                      selected: _hasSearchMatch && _index == index,
                      child: Material(
                        color: _hasSearchMatch && _index == index
                            ? Colors.white.withValues(alpha: .065)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: ValueKey(
                            row.isNew
                                ? 'new-agent-folder-newProject'
                                : row.repository != null
                                ? 'new-agent-clone-project'
                                : 'project-${row.path}',
                          ),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _select(row),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Icon(
                                  row.isNew
                                      ? LucideIcons.plus
                                      : row.repository != null
                                      ? LucideIcons.gitBranch
                                      : LucideIcons.folder,
                                  size: 18,
                                  color: grid.AppPalette.textSecondary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (row.path != null ||
                                          row.repository != null)
                                        Text(
                                          row.path ?? 'Clone repository',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                grid.AppPalette.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_hasSearchMatch && _index == index)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.keyboard_return,
                                      size: 16,
                                      color: grid.AppPalette.textFaint,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final list = Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(height: _rowHeight, child: projectRow(0)),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _listScroll,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: rows.length - 1,
                        itemExtent: _rowHeight,
                        itemBuilder: (context, index) => projectRow(index + 1),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: TextButton.icon(
                          key: const Key('new-agent-project-browse'),
                          style: TextButton.styleFrom(
                            foregroundColor: grid.AppPalette.textSecondary,
                          ),
                          onPressed: _browsing ? null : _browse,
                          icon: const Icon(LucideIcons.folderOpen, size: 16),
                          label: Text(
                            _browsing ? 'Opening…' : 'Browse folders…',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                final preview = !_hasSearchMatch
                    ? Center(
                        child: Text(
                          'No matching projects',
                          style: TextStyle(
                            color: grid.AppPalette.textSecondary,
                          ),
                        ),
                      )
                    : _ProjectPreview(row: rows[_index], data: _preview);
                return SizedBox(
                  height: wide
                      ? math.min(
                          330,
                          math.max(
                            260,
                            MediaQuery.sizeOf(context).height - 520,
                          ),
                        )
                      : 430,
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: list),
                            const SizedBox(width: 16),
                            Expanded(child: preview),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(height: 230, child: list),
                            Expanded(child: preview),
                          ],
                        ),
                );
              },
            ),
          if (_open) const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ProjectPreview extends StatelessWidget {
  const _ProjectPreview({required this.row, required this.data});
  final _ProjectRow row;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(
      fontSize: 12,
      color: grid.AppPalette.textSecondary,
      height: 1.5,
    );
    final readme = data?['readme'];
    final commit = data?['commit'];
    final contributors = data?['contributors'];
    final files = data?['files'];
    return SingleChildScrollView(
      key: ValueKey('project-preview-${row.path ?? row.name}'),
      padding: const EdgeInsets.fromLTRB(16, 18, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            row.path ?? (row.repository?.url ?? '~/harnesses'),
            style: secondary,
          ),
          if (row.repository != null) ...[
            const SizedBox(height: 24),
            Text('Cloned when you create the agent.', style: secondary),
          ],
          if (row.path != null && data == null) ...[
            const SizedBox(height: 24),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          if (data?['error'] != null) ...[
            const SizedBox(height: 24),
            Text(
              data?['error'] == 'NOT_FOUND'
                  ? 'Folder unavailable'
                  : 'Preview unavailable',
              style: secondary,
            ),
          ],
          if (data?['branch'] is String || data?['changedFiles'] is int) ...[
            const SizedBox(height: 16),
            Text(
              [
                if (data?['branch'] is String) data!['branch'],
                if (data?['changedFiles'] is int && data!['changedFiles'] > 0)
                  '${data!['changedFiles']} changed files',
              ].join(' · '),
              style: secondary,
            ),
          ],
          if (readme is String && readme.trim().isNotEmpty) ...[
            const SizedBox(height: 24),
            ..._readme(context, readme),
          ] else if (files is List && files.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final file in files.whereType<String>())
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(file, style: secondary),
              ),
          ],
          if (commit is Map && commit['subject'] is String) ...[
            const SizedBox(height: 24),
            Text('Latest commit', style: secondary),
            const SizedBox(height: 5),
            Text(
              commit['subject'],
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if (commit['author'] is String)
              Text(
                [
                  commit['author'],
                  if (commit['date'] is String)
                    (commit['date'] as String).split('T').first,
                ].join(' · '),
                style: secondary,
              ),
          ],
          if (contributors is List && contributors.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Contributors', style: secondary),
            const SizedBox(height: 5),
            Text(
              contributors.whereType<String>().join(' · '),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  /// A restrained excerpt: headings, paragraphs and code remain readable.
  /// Links are text; Markdown never fetches remote images or runs HTML.
  List<Widget> _readme(BuildContext context, String text) {
    final result = <Widget>[];
    var code = false;
    for (final raw
        in text
            .substring(0, math.min(text.length, 5000))
            .split('\n')
            .take(70)) {
      if (raw.trim().startsWith('```')) {
        code = !code;
        continue;
      }
      if (raw.trim().startsWith('<') || raw.trim().startsWith('![')) continue;
      final heading = RegExp(r'^#{1,6}\s+').hasMatch(raw);
      final line = raw
          .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
          .replaceAllMapped(
            RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
            (match) => match.group(1)!,
          )
          .replaceAll('**', '')
          .replaceAll('`', '');
      result.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: line.isEmpty ? 4 : 6,
            top: heading ? 8 : 0,
          ),
          child: Text(
            line,
            style: TextStyle(
              fontSize: heading ? 17 : 13,
              height: 1.55,
              fontWeight: heading ? FontWeight.w600 : FontWeight.normal,
              fontFamily: code ? grid.AppFont.mono : null,
              color: grid.AppPalette.textPrimary.withValues(
                alpha: heading ? 1 : .85,
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }
}
