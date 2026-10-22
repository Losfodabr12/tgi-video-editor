import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = [
    (
      name: 'identical texts',
      reference: 'ola mundo',
      hypothesis: 'ola mundo',
      expected: 'palavras ref=2 hip=2\nWER=0.00%  CER=0.00%\n',
    ),
    (
      name: 'one substituted word',
      reference: 'ola mundo',
      hypothesis: 'ola lindo',
      expected: 'palavras ref=2 hip=2\nWER=50.00%  CER=22.22%\n',
    ),
    (
      name: 'one omitted word',
      reference: 'ola mundo',
      hypothesis: 'ola',
      expected: 'palavras ref=2 hip=1\nWER=50.00%  CER=66.67%\n',
    ),
    (
      name: 'accent differences count as errors',
      reference: 'caf\u00e9',
      hypothesis: 'cafe',
      expected: 'palavras ref=1 hip=1\nWER=100.00%  CER=25.00%\n',
    ),
    (
      name: 'case and punctuation differences are ignored',
      reference: 'Ol\u00e1, MUNDO!',
      hypothesis: 'ol\u00e1 mundo',
      expected: 'palavras ref=2 hip=2\nWER=0.00%  CER=0.00%\n',
    ),
  ];

  for (final sample in cases) {
    test('WER CLI: ${sample.name}', () async {
      final temporary = await Directory.systemTemp.createTemp('tgi-wer-test-');
      addTearDown(() => temporary.delete(recursive: true));
      final reference = File('${temporary.path}/reference.txt');
      final hypothesis = File('${temporary.path}/hypothesis.txt');
      await reference.writeAsString(sample.reference);
      await hypothesis.writeAsString(sample.hypothesis);

      // Exercise the supplied script through its public command line.
      final result = await Process.run(
        'dart',
        ['tools/wer.dart', reference.path, hypothesis.path],
        workingDirectory: Directory.current.parent.path,
        runInShell: Platform.isWindows,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stderr.toString(), isEmpty);
      expect(
        result.stdout.toString().replaceAll('\r\n', '\n'),
        sample.expected,
      );
    });
  }
}
