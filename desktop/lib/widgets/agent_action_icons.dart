import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Agent actions use + to create and ↗ to open. Search fields keep their lens.
/// The native menu/titlebar match these with `plus` and `arrow.up.right`.
abstract final class AgentActionIcons {
  static const create = LucideIcons.plus300;
  static const open = LucideIcons.arrowUpRight300;
}
