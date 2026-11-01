import 'dart:typed_data';

class AvatarImageData {
  const AvatarImageData({required this.bytes, required this.contentType});

  static const maxDimension = 512;
  static const quality = 0.9;

  final Uint8List bytes;
  final String contentType;
}
