import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/repository_clone.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../shared/widgets/labeled_field.dart';

Future<String?> showCloneRepositoryDialog(
  BuildContext context, {
  String? initialFolder,
}) => showAppDialog<String>(
  context: context,
  builder: (_) => CloneRepositoryDialog(initialFolder: initialFolder),
);

class CloneRepositoryDialog extends StatefulWidget {
  const CloneRepositoryDialog({
    super.key,
    this.initialFolder,
    this.createClone,
  });
  final String? initialFolder;
  final RepositoryClone Function()? createClone;
  @override
  State<CloneRepositoryDialog> createState() => _CloneRepositoryDialogState();
}

class _CloneRepositoryDialogState extends State<CloneRepositoryDialog> {
  final _url = TextEditingController();
  String? _parent, _error;
  RepositoryClone? _clone;
  bool _picking = false, _closing = false;
  bool get _busy => _clone != null;
  GitHubRepository? get _repository => GitHubRepository.parse(_url.text);

  @override
  void dispose() {
    _clone?.cancel();
    _url.dispose();
    super.dispose();
  }

  Future<void> _chooseDestination() async {
    setState(() => _picking = true);
    try {
      final folder = await getDirectoryPath(
        initialDirectory:
            _parent ??
            (widget.initialFolder == null
                ? null
                : p.dirname(widget.initialFolder!)),
        confirmButtonText: 'Choose destination',
      );
      if (mounted && folder != null) {
        setState(() {
          _parent = folder;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the folder picker. Try again.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    final repository = _repository, parent = _parent;
    if (repository == null || parent == null || _busy) return;
    final clone = widget.createClone?.call() ?? RepositoryClone();
    setState(() {
      _clone = clone;
      _error = null;
    });
    String? result;
    try {
      result = await clone.run(repository, parent);
    } on RepositoryCloneException catch (error) {
      if (mounted && !_closing) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && !_closing) {
        setState(
          () => _error = 'Could not clone the repository. Please retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _clone = null);
        if (result != null || _closing) Navigator.pop(context, result);
      }
    }
  }

  void _cancel() {
    if (_busy) {
      setState(() => _closing = true);
      _clone!.cancel();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final repository = _repository;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Clone repository'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('GitHub repository'),
                TextField(
                  key: const ValueKey('clone-repository-url'),
                  controller: _url,
                  autofocus: true,
                  readOnly: _busy,
                  decoration: const InputDecoration(
                    hintText: 'https://github.com/owner/repository',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use an HTTPS or SSH URL, or owner/repository.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                const FieldLabel('Destination on this computer'),
                OutlinedButton.icon(
                  onPressed: _busy || _picking ? null : _chooseDestination,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(
                    _parent ?? 'Choose folder…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    foregroundColor: grid.AppPalette.textPrimary,
                  ),
                ),
                if (_parent != null && repository != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Creates ${p.join(_parent!, repository.name)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 8),
                  Text(
                    _closing ? 'Cancelling…' : 'Cloning ${repository!.name}…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _closing ? null : _cancel,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed:
                _busy || _picking || repository == null || _parent == null
                ? null
                : _submit,
            child: const Text('Clone repository'),
          ),
        ],
      ),
    );
  }
}
