/// Which domain-specific harnesses one machine has, or could install, as that
/// machine answered it (`dsh_list` in the CLI's backendSocket).
///
/// A harness is installed PER MACHINE — it is a clone under `~/.harness/dsh`
/// on the box the agent will run on, with that box's toolchain set up beside
/// it — so, exactly like [MachineEngines], the answer is asked of the machine
/// and rendered, never computed here. The catalog the daemon merges in (the
/// registry bundled into the CLI) is what lets the Create dialog offer Circuit
/// on a machine that has never heard of it and say "Harness will install".
library;

class DshEntry {
  const DshEntry({
    required this.id,
    required this.name,
    required this.engine,
    this.description,
    this.category,
    this.installed = false,
    this.viewer = false,
    this.tier = 0,
  });

  /// `owner/name` — the install directory on the machine and the wire id.
  final String id;

  /// The tile's name, as the manifest or the registry spells it.
  final String name;

  /// The base engine the harness runs on: what `agent_create` must be sent.
  final String engine;
  final String? description;

  /// The kind of thing it makes, in a word or two — the picker's second line.
  final String? category;
  final bool installed;

  /// Whether it ships a viewer, i.e. whether a web pane will open beside it.
  final bool viewer;
  final int tier;

  static DshEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final engine = raw['engine'];
    if (id is! String || !_validId(id)) return null;
    if (engine is! String || engine.isEmpty || engine.length > 64) return null;
    final name = raw['name'];
    final description = raw['description'];
    final category = raw['category'];
    final tier = raw['tier'];
    return DshEntry(
      id: id,
      name: name is String && name.trim().isNotEmpty
          ? name.trim().substring(0, name.trim().length.clamp(0, 40))
          : id.substring(id.indexOf('/') + 1),
      engine: engine,
      description: description is String && description.trim().isNotEmpty
          ? description.trim().substring(
              0,
              description.trim().length.clamp(0, 300),
            )
          : null,
      category: category is String && category.trim().isNotEmpty
          ? category.trim().substring(0, category.trim().length.clamp(0, 24))
          : null,
      installed: raw['installed'] == true,
      viewer: raw['viewer'] == true,
      tier: tier is num && tier >= 0 && tier <= 9 ? tier.toInt() : 0,
    );
  }

  static bool _validId(String id) =>
      id.length <= 129 &&
      RegExp(r'^[a-z0-9][a-z0-9-]{0,63}/[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id);
}

/// Where an install the user asked for stands, as the machine reports it
/// (`dsh_install_status` pushes: clone → setup → doctor → done, or failed).
class DshInstallProgress {
  const DshInstallProgress({
    required this.id,
    required this.phase,
    this.detail,
  });

  final String id;
  final String phase;
  final String? detail;

  bool get done => phase == 'done';
  bool get failed => phase == 'failed';
  bool get inProgress => !done && !failed;

  /// A sentence for the dialog's status line.
  String get label => switch (phase) {
    'clone' => 'Fetching…',
    'setup' => 'Setting up the toolchain…',
    'doctor' => 'Checking the machine…',
    'done' => 'Installed',
    'failed' => detail?.isNotEmpty == true ? detail! : 'Install failed',
    _ => 'Installing…',
  };

  static DshInstallProgress? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final phase = raw['phase'];
    if (id is! String || id.isEmpty || phase is! String || phase.isEmpty) {
      return null;
    }
    final detail = raw['detail'];
    return DshInstallProgress(
      id: id,
      phase: phase,
      detail: detail is String && detail.trim().isNotEmpty
          ? detail
                .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
                .trim()
                .substring(0, detail.trim().length.clamp(0, 500))
          : null,
    );
  }
}

/// One machine's answers, with the same "still asking" versus "asked, and it
/// has nothing" distinction [MachineEngines] keeps — a tile must not read as
/// "not installed" on the strength of a request that has not come back.
class MachineDsh {
  MachineDsh();

  final Map<String, DshEntry> byId = {};

  /// True once `dsh_list` has answered at least once. Never reset by a
  /// refresh, so the rows already on screen stay put while a new answer lands.
  bool loaded = false;

  /// A request is in flight. Held so a dialog opening twice does not start two.
  Future<void>? inFlight;

  /// Set when the machine could not answer — an older CLI that does not know
  /// the request, or a transport failure. The dialog still offers the harnesses
  /// this build ships a face for; the machine decides at create time.
  String? error;

  /// Installs the user asked for, by harness id, at their latest reported phase.
  final Map<String, DshInstallProgress> installs = {};

  DshEntry? operator [](String id) => byId[id];

  /// Every harness the machine named, installed or not, in the order it gave.
  List<DshEntry> get entries => byId.values.toList(growable: false);

  void replace(Iterable<DshEntry> found) {
    byId
      ..clear()
      ..addEntries(found.map((entry) => MapEntry(entry.id, entry)));
    loaded = true;
    error = null;
  }
}
