import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../bin/skills.dart';

void main() {
  late Directory tempDir;
  late Uri skillsRoot;

  const expectedSkills = [
    'soundfont_kit-filters',
    'soundfont_kit-idioms',
    'soundfont_kit-loading',
    'soundfont_kit-playback',
    'soundfont_kit-preloading',
    'soundfont_kit-scheduling',
    'soundfont_kit-sustain',
  ];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('soundfont_kit_skills_test_');
    skillsRoot = Directory.current.uri.resolve('skills/');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Agent Skills installer', () {
    test('discovers all bundled skills and defaults to .agents home', () async {
      final plan = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );

      expect(plan.action, SkillInstallAction.install);
      expect(plan.homes, ['.agents/skills']);
      expect(plan.skillNames.length, 7);
      expect(plan.installCount, 7);
      expect(plan.updateCount, 0);
      for (final skill in expectedSkills) {
        expect(plan.skillNames, contains(skill));
      }
    });

    test(
      'installs all skills into default .agents/skills and is idempotent',
      () async {
        final result = await installSkills(
          projectRoot: tempDir,
          skillsRoot: skillsRoot,
        );

        expect(
          result,
          contains(
            'Installed 7 soundfont_kit agent skills into .agents/skills.',
          ),
        );

        for (final skill in expectedSkills) {
          final skillFile = File.fromUri(
            tempDir.uri.resolve('.agents/skills/$skill/SKILL.md'),
          );
          expect(
            skillFile.existsSync(),
            isTrue,
            reason: '$skill/SKILL.md should exist',
          );
        }

        // Subsequent plan should be upToDate
        final planAfter = await planSkillInstall(
          projectRoot: tempDir,
          skillsRoot: skillsRoot,
        );
        expect(planAfter.action, SkillInstallAction.upToDate);
        expect(planAfter.installCount, 0);
        expect(planAfter.updateCount, 0);
      },
    );

    test('installs into all present agent homes', () async {
      // Create .claude and .cursor directories in the project root
      Directory.fromUri(tempDir.uri.resolve('.claude/')).createSync();
      Directory.fromUri(tempDir.uri.resolve('.cursor/')).createSync();

      final plan = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );

      expect(plan.homes, ['.claude/skills', '.cursor/skills']);

      await installSkills(projectRoot: tempDir, skillsRoot: skillsRoot);

      for (final skill in expectedSkills) {
        final claudeSkill = File.fromUri(
          tempDir.uri.resolve('.claude/skills/$skill/SKILL.md'),
        );
        final cursorSkill = File.fromUri(
          tempDir.uri.resolve('.cursor/skills/$skill/SKILL.md'),
        );
        expect(claudeSkill.existsSync(), isTrue);
        expect(cursorSkill.existsSync(), isTrue);
      }

      // .agents should not be created when other agent homes exist
      final agentsDir = Directory.fromUri(tempDir.uri.resolve('.agents/'));
      expect(agentsDir.existsSync(), isFalse);
    });

    test('detects stale versions and updates them', () async {
      await installSkills(projectRoot: tempDir, skillsRoot: skillsRoot);

      // Modify installed skill to have version: 0
      final file = File.fromUri(
        tempDir.uri.resolve('.agents/skills/soundfont_kit-idioms/SKILL.md'),
      );
      final content = file.readAsStringSync().replaceFirst(
        'version: 1',
        'version: 0',
      );
      file.writeAsStringSync(content);

      final plan = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );

      expect(plan.action, SkillInstallAction.update);
      expect(plan.updateCount, 1);
      expect(
        describeSkillPlan(plan),
        contains(
          '1 soundfont_kit agent skill(s) have a newer version available',
        ),
      );

      // Re-installing updates it
      await installSkills(projectRoot: tempDir, skillsRoot: skillsRoot);

      final planAfter = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );
      expect(planAfter.action, SkillInstallAction.upToDate);
    });

    test('CLI --check exit code reflects installation state', () async {
      final binScript = Directory.current.uri
          .resolve('bin/skills.dart')
          .toFilePath();
      final dartExe = Platform.executable.endsWith('flutter_tester')
          ? 'dart'
          : Platform.executable;

      // Check on uninstalled tempDir -> exit code 1
      final resultBefore = Process.runSync(dartExe, [
        binScript,
        '--check',
        '--project-root',
        tempDir.path,
      ]);
      expect(resultBefore.exitCode, 1);
      expect(resultBefore.stdout.toString(), contains('are not installed'));

      // Run installation CLI
      final installResult = Process.runSync(dartExe, [
        binScript,
        '--project-root',
        tempDir.path,
      ]);
      expect(installResult.exitCode, 0);
      expect(
        installResult.stdout.toString(),
        contains('Installed 7 soundfont_kit agent skills'),
      );

      // Check on installed tempDir -> exit code 0
      final resultAfter = Process.runSync(dartExe, [
        binScript,
        '--check',
        '--project-root',
        tempDir.path,
      ]);
      expect(resultAfter.exitCode, 0);
      expect(
        resultAfter.stdout.toString(),
        contains(
          'The soundfont_kit agent skills are up to date (7 installed).',
        ),
      );
    });
  });
}
