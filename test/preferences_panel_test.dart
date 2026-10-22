import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_video/core/domain/output_profile.dart';
import 'package:nexus_video/core/domain/preferences.dart';
import 'package:nexus_video/ui/views/preferences_view.dart';

void main() {
  test('preferences equality detects field and profile changes', () {
    final base = Preferences();
    expect(preferencesEqual(base, base.copyWith()), isTrue);
    expect(preferencesEqual(base, base.copyWith(parallelJobs: 4)), isFalse);
    expect(
      preferencesEqual(base, base.copyWith(pathTemplate: '{title}')),
      isFalse,
    );
    expect(
      preferencesEqual(
        base,
        base.copyWith(
          profiles: const [
            OutputProfile(id: 'custom', name: '自定义', builtIn: false),
          ],
        ),
      ),
      isFalse,
    );
  });

  test('panel controller reports dirty state and runs save', () async {
    var dirty = false;
    var saved = false;
    final controller = PreferencesPanelController();
    controller.attach(
      isDirty: () => dirty,
      save: () async {
        saved = true;
        return true;
      },
    );

    expect(controller.isDirty, isFalse);
    dirty = true;
    expect(controller.isDirty, isTrue);
    expect(await controller.save(), isTrue);
    expect(saved, isTrue);

    controller.detach();
    expect(controller.isDirty, isFalse);
  });
}
