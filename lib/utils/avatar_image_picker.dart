import 'avatar_image_data.dart';
import 'avatar_image_picker_stub.dart'
    if (dart.library.js_interop) 'avatar_image_picker_web.dart'
    as implementation;

export 'avatar_image_data.dart';

Future<AvatarImageData?> pickWebAvatar() => implementation.pickWebAvatar();
