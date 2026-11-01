import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AvatarImage extends StatelessWidget {
  const AvatarImage({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double size;
  final Widget fallback;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return fallback;

    if (kIsWeb) {
      return Image.network(
        url!,
        width: size,
        height: size,
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return fallback;
        },
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: url!,
      width: size,
      height: size,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
