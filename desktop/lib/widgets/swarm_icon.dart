import 'package:flutter/cupertino.dart';

/// Four agents sharing one workspace. Native menus use the corresponding
/// `square.split.2x2` symbol in SwarmTitlebar.swift.
class SwarmIcon extends StatelessWidget {
  const SwarmIcon({super.key, this.size = 19, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Icon(CupertinoIcons.square_split_2x2, size: size, color: color);
}
