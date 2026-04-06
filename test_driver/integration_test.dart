// Host-side driver for integration_test screenshots. Receives screenshot
// bytes from the device/simulator over the VM service and writes them to
// build/screenshots/ on the host. Launched by scripts/generate_screenshots.sh
// via `flutter drive --driver=test_driver/integration_test.dart ...`.

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes,
        [Map<String, Object?>? args]) async {
      final file = File('build/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
