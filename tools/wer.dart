import 'dart:io';
import 'dart:math';

String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int editDistance<T>(List<T> a, List<T> b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('uso: dart tools/wer.dart referencia.txt hipotese.txt');
    exit(2);
  }
  final ref = normalize(File(args[0]).readAsStringSync());
  final hyp = normalize(File(args[1]).readAsStringSync());
  final rw = ref.isEmpty ? <String>[] : ref.split(' ');
  final hw = hyp.isEmpty ? <String>[] : hyp.split(' ');
  final rc = ref.runes.toList(), hc = hyp.runes.toList();
  final wer = rw.isEmpty ? 0.0 : editDistance(rw, hw) / rw.length * 100;
  final cer = rc.isEmpty ? 0.0 : editDistance(rc, hc) / rc.length * 100;
  stdout.writeln('palavras ref=${rw.length} hip=${hw.length}');
  stdout.writeln('WER=${wer.toStringAsFixed(2)}%  CER=${cer.toStringAsFixed(2)}%');
}
