import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/services/image_probe_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  test('inspects required 2198x367 PNG dimensions and alpha range', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_probe_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'master.png'));

    final image = img.Image(width: 2198, height: 367, numChannels: 4);
    img.fill(image, color: img.ColorUint8.rgba(10, 20, 30, 255));
    image.setPixelRgba(0, 0, 10, 20, 30, 0);
    await file.writeAsBytes(img.encodePng(image));

    final probe = await ImageProbeService().inspect(file.path);

    expect(probe.width, 2198);
    expect(probe.height, 367);
    expect(probe.hasAlpha, isTrue);
    expect(probe.alphaMin, 0);
    expect(probe.alphaMax, 255);
    expect(probe.isRequiredPreviewSize, isTrue);
  });

  test('throws a format exception for unreadable image files', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_probe_bad_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'bad.png'));
    await file.writeAsString('not a png');

    expect(
      () => ImageProbeService().inspect(file.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts an arbitrary-size ultra-wide JPEG', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_probe_jpg_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'wallpaper.jpg'));
    final image = img.Image(width: 8960, height: 1320);
    await file.writeAsBytes(img.encodeJpg(image, quality: 92));

    final probe = await ImageProbeService().inspect(file.path);

    expect(probe.width, 8960);
    expect(probe.height, 1320);
    expect(probe.isUltraClearSize, isTrue);
    expect(probe.hasUltraWideAspectRatio, isTrue);
    expect(probe.qualityLabel, '原生超清');
  });
}
