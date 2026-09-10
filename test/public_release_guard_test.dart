import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release bundles the six verified factory OTA templates', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final gitignore = await File('.gitignore').readAsString();
    final buildKitScript =
        await File('scripts/make_windows_build_kit.sh').readAsString();
    final templateDirectory = Directory('packager/templates');
    final templateZips = await templateDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zip'))
        .map((entity) => entity.uri.pathSegments.last)
        .toList();

    expect(
      templateZips.toSet(),
      <String>{
        'BFA3A0F4596C4C57A6BCDC1EB3348932.zip',
        'C59D070C944F434488DBB47F3A1856B4.zip',
        '1DE01DE2BDE840B5B80A2CBA4069C63A.zip',
        '9ADAF72DC26C4442A4FDA635FABCA348.zip',
        '36DBC54BD479499FB8D3585D7A3CE184.zip',
        '485EACC2AAC04B0291C769D74E938AE6.zip',
      },
    );
    expect(
      pubspec,
      contains('packager/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip'),
    );
    expect(pubspec, contains('1DE01DE2BDE840B5B80A2CBA4069C63A.zip'));
    expect(pubspec, contains('C59D070C944F434488DBB47F3A1856B4.zip'));
    expect(pubspec, contains('9ADAF72DC26C4442A4FDA635FABCA348.zip'));
    expect(pubspec, contains('36DBC54BD479499FB8D3585D7A3CE184.zip'));
    expect(pubspec, contains('485EACC2AAC04B0291C769D74E938AE6.zip'));
    expect(gitignore, contains('packager/templates/*.zip'));
    expect(
      gitignore,
      contains('!packager/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip'),
    );
    expect(gitignore,
        contains('!packager/templates/1DE01DE2BDE840B5B80A2CBA4069C63A.zip'));
    expect(gitignore,
        contains('!packager/templates/C59D070C944F434488DBB47F3A1856B4.zip'));
    expect(gitignore,
        contains('!packager/templates/9ADAF72DC26C4442A4FDA635FABCA348.zip'));
    expect(gitignore,
        contains('!packager/templates/36DBC54BD479499FB8D3585D7A3CE184.zip'));
    expect(gitignore,
        contains('!packager/templates/485EACC2AAC04B0291C769D74E938AE6.zip'));
    expect(buildKitScript, contains("'packager/templates/*.zip'"));
    expect(
      buildKitScript,
      contains('packager/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip'),
    );
    expect(buildKitScript, contains('1DE01DE2BDE840B5B80A2CBA4069C63A.zip'));
    expect(buildKitScript, contains('C59D070C944F434488DBB47F3A1856B4.zip'));
    expect(buildKitScript, contains('9ADAF72DC26C4442A4FDA635FABCA348.zip'));
    expect(buildKitScript, contains('36DBC54BD479499FB8D3585D7A3CE184.zip'));
    expect(buildKitScript, contains('485EACC2AAC04B0291C769D74E938AE6.zip'));
  });

  test('public docs do not contain local user paths', () async {
    final docs = <String>[
      'README.md',
      'README.zh-CN.md',
      'CONTRIBUTING.md',
      'SECURITY.md',
      'DISCLAIMER.md',
      'THIRD_PARTY_NOTICES.md',
      'docs/open-source-release-checklist.md',
      'docs/usage-zh-CN.md',
      'docs/release-notes-v1.0.0.md',
      'docs/release-notes-v1.0.1.md',
      'docs/release-notes-v1.0.5.md',
      'WINDOWS_BUILD_README.txt',
    ];
    final localPathPattern = RegExp(
      r'(/Users/[A-Za-z0-9._-]+|C:\\Users\\[A-Za-z0-9._-]+)',
    );

    for (final path in docs) {
      final content = await File(path).readAsString();
      expect(content, isNot(matches(localPathPattern)), reason: path);
    }
  });
}
