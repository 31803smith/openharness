import '../core/config.dart';
import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';

/// Persists user-configurable connection settings in the Harness home file.
class ConfigStore {
  final LocalKeyValueStore _storage;
  static const _baseUrlKey = 'app_api_base_url';
  static const _environmentKey = 'app_autonomous_environment';
  static const _skippedDesktopUpdateVersionKey =
      'skipped_desktop_update_version';
  // "Don't show this again" on the Run a local model dialog. Here rather than
  // beside the pane layout because it is a choice about the PERSON, not about
  // a machine or a tab: somebody who has watched the explanation once does not
  // need it again for their second computer either.
  static const _runLocalModelSkipDialogKey = 'runLocalModel.skipDialog';
  // No longer read or written: live pre-flight runs on every launch. Kept only
  // so Reset can clean state written by older desktop builds.
  static const _legacyEnvironmentSetupVersionKey = 'environment_setup_version';
  static const String defaultBaseUrl = 'https://harness-api.autonomous.ai';

  ConfigStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared;

  AppConfig get config => AppConfig(
    apiBaseUrl: _cachedBaseUrl ?? defaultBaseUrl,
    autonomousEnv: _cachedEnvironment ?? 'prod',
  );
  String? _cachedBaseUrl;
  String? _cachedEnvironment;
  String? _cachedSkippedDesktopUpdateVersion;
  bool _cachedRunLocalModelSkipDialog = false;

  String? get skippedDesktopUpdateVersion => _cachedSkippedDesktopUpdateVersion;

  /// Whether the Run a local model dialog has been waved off for good. False
  /// until [load] or [saveRunLocalModelSkipDialog] says otherwise, so a store
  /// that was never read still shows the explanation — the safe direction.
  bool get runLocalModelSkipDialog => _cachedRunLocalModelSkipDialog;

  Future<AppConfig> load() async {
    // Keep the tiny startup path sequential and predictable.
    final baseUrl = await _storage.read(_baseUrlKey);
    final environment = await _storage.read(_environmentKey);
    final skippedUpdate = await _storage.read(_skippedDesktopUpdateVersionKey);
    final skipRunLocalModel = await _storage.read(_runLocalModelSkipDialogKey);
    _cachedBaseUrl = baseUrl ?? defaultBaseUrl;
    _cachedEnvironment = environment == 'stag' ? 'stag' : 'prod';
    _cachedSkippedDesktopUpdateVersion = skippedUpdate?.trim().isEmpty ?? true
        ? null
        : skippedUpdate!.trim();
    _cachedRunLocalModelSkipDialog = skipRunLocalModel == 'true';
    return config;
  }

  Future<void> saveRunLocalModelSkipDialog(bool value) async {
    _cachedRunLocalModelSkipDialog = value;
    if (value) {
      await _storage.write(_runLocalModelSkipDialogKey, 'true');
    } else {
      await _storage.delete(_runLocalModelSkipDialogKey);
    }
  }

  Future<void> save(String baseUrl) async {
    _cachedBaseUrl = baseUrl;
    await _storage.write(_baseUrlKey, baseUrl);
  }

  Future<void> saveEnvironment(String autonomousEnv) async {
    _cachedEnvironment = autonomousEnv == 'stag' ? 'stag' : 'prod';
    await _storage.write(_environmentKey, _cachedEnvironment!);
  }

  Future<void> saveSkippedDesktopUpdateVersion(String? version) async {
    final normalized = version?.trim();
    _cachedSkippedDesktopUpdateVersion =
        normalized == null || normalized.isEmpty ? null : normalized;
    if (_cachedSkippedDesktopUpdateVersion == null) {
      await _storage.delete(_skippedDesktopUpdateVersionKey);
    } else {
      await _storage.write(
        _skippedDesktopUpdateVersionKey,
        _cachedSkippedDesktopUpdateVersion!,
      );
    }
  }

  Future<void> reset() async {
    _cachedBaseUrl = null;
    _cachedEnvironment = null;
    _cachedSkippedDesktopUpdateVersion = null;
    _cachedRunLocalModelSkipDialog = false;
    await Future.wait([
      _storage.delete(_baseUrlKey),
      _storage.delete(_environmentKey),
      _storage.delete(_skippedDesktopUpdateVersionKey),
      _storage.delete(_runLocalModelSkipDialogKey),
      _storage.delete(_legacyEnvironmentSetupVersionKey),
    ]);
  }
}
