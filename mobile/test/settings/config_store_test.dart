import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/core/local_key_value_store.dart';
import 'package:harness_mobile/settings/config_store.dart';

/// The connection settings the phone reads once, at the top of every launch
/// (`AppNotifier.bootstrap`), before it knows which backend to sign in to.
///
/// Only the read is the phone's: the writes behind it (a base URL, the staging
/// switch, a skipped desktop update) have no screen on a phone, and are left to
/// the desktop's own suite.
void main() {
  test('before anything is read it points at production', () {
    // Touches the shared file store's constructor only — no read, no IO.
    final config = ConfigStore().config;
    expect(config.apiBaseUrl, ConfigStore.defaultBaseUrl);
    expect(config.autonomousEnv, 'prod');
  });

  test('nothing saved: production, and no skipped update', () async {
    final store = ConfigStore(storage: _Store({}));
    final config = await store.load();
    expect(config.apiBaseUrl, ConfigStore.defaultBaseUrl);
    expect(config.autonomousEnv, 'prod');
    expect(store.skippedDesktopUpdateVersion, isNull);
  });

  test('what was saved comes back, in one batched read', () async {
    final storage = _Store({
      'app_api_base_url': 'https://staging.example',
      'app_autonomous_environment': 'stag',
      'skipped_desktop_update_version': '  1.4.0 ',
    });
    final store = ConfigStore(storage: storage);
    final config = await store.load();
    expect(config.apiBaseUrl, 'https://staging.example');
    expect(config.autonomousEnv, 'stag');
    expect(store.skippedDesktopUpdateVersion, '1.4.0');
    expect(store.config.apiBaseUrl, 'https://staging.example');
    // `readMany`, never three reads: each read on the real store takes the
    // file lock and re-parses `state.json` on the launch path.
    expect(storage.batches, 1);
    expect(storage.reads, 0);
  });

  test('an environment that is not staging is production', () async {
    final store = ConfigStore(
      storage: _Store({
        'app_autonomous_environment': 'Stag ',
        'skipped_desktop_update_version': '   ',
      }),
    );
    final config = await store.load();
    expect(config.autonomousEnv, 'prod');
    expect(store.skippedDesktopUpdateVersion, isNull);
  });
}

/// An in-memory `state.json` that counts how it was asked.
class _Store implements BatchLocalKeyValueStore {
  _Store(this.values);

  final Map<String, String> values;
  int batches = 0;
  int reads = 0;

  @override
  Future<Map<String, String?>> readMany(Iterable<String> keys) async {
    batches++;
    return {for (final key in keys) key: values[key]};
  }

  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
