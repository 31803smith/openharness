/// Built-in backgrounds for empty Harness pages. Wallpaper never covers agents.
enum HarnessBackground {
  plain('Default'),
  aurora('Aurora'),
  lake('Lake', 'swarm-welcome-dusk.jpg'),
  silk('Silk', 'swarm-welcome-abstract.jpg'),
  threads('Threads', 'swarm-welcome-associative-memory.jpg'),
  constellation('Constellation', 'swarm-welcome-ai.jpg');

  const HarnessBackground(this.label, [this.fileName]);
  final String label;
  final String? fileName;
  String? get asset =>
      fileName == null ? null : 'assets/swarm-wallpapers/$fileName';

  static HarnessBackground fromId(String? id) =>
      values.where((value) => value.name == id).firstOrNull ?? plain;
}
