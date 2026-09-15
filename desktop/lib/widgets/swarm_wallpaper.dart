import 'dart:async';

import 'package:flutter/material.dart';

/// Wallpaper belongs only to the empty new-swarm canvas.
class SwarmWallpaper extends StatefulWidget {
  const SwarmWallpaper({super.key});

  @override
  State<SwarmWallpaper> createState() => _SwarmWallpaperState();
}

class _SwarmWallpaperState extends State<SwarmWallpaper> {
  static const _image = AssetImage(
    'assets/swarm-wallpapers/swarm-welcome-dusk.jpg',
  );
  ImageConfiguration _configuration = ImageConfiguration.empty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configuration = createLocalImageConfiguration(context);
  }

  @override
  void dispose() {
    // Populated swarms do not retain a decoded welcome image in Flutter's
    // keep-alive cache. Evict only our asset, leaving terminal images alone.
    unawaited(_image.evict(configuration: _configuration));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image(
        image: _image,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1211111c), Color(0x750c111e)],
          ),
        ),
      ),
    ],
  );
}
