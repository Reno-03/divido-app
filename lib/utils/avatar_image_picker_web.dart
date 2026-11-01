import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'avatar_image_data.dart';

Future<AvatarImageData?> pickWebAvatar() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  input.click();
  await input.onChange.first;

  final files = input.files;
  if (files == null || files.length == 0) return null;

  final file = files.item(0)!;
  if (file.type.isNotEmpty && !file.type.startsWith('image/')) {
    throw const FormatException('Please select an image file.');
  }

  final image = await web.window.createImageBitmap(file).toDart;
  try {
    final scale = math.min(
      1.0,
      AvatarImageData.maxDimension / math.max(image.width, image.height),
    );
    final width = math.max(1, (image.width * scale).round());
    final height = math.max(1, (image.height * scale).round());
    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) {
      throw StateError('Could not prepare the selected image.');
    }

    context
      ..fillStyle = '#ffffff'.toJS
      ..fillRect(0, 0, width, height)
      ..drawImage(image, 0, 0, width, height);

    final blobCompleter = Completer<web.Blob>();
    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null) {
          blobCompleter.completeError(
            StateError('Could not compress the selected image.'),
          );
        } else {
          blobCompleter.complete(blob);
        }
      }).toJS,
      'image/jpeg',
      AvatarImageData.quality.toJS,
    );
    final blob = await blobCompleter.future;
    final buffer = await blob.arrayBuffer().toDart;
    return AvatarImageData(
      bytes: Uint8List.view(buffer.toDart),
      contentType: 'image/jpeg',
    );
  } finally {
    image.close();
  }
}
