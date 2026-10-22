// SPDX-License-Identifier: BSD-3-Clause
// Synthetic worker: never loads PC/SC or the application backend.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final mode = args[0], marker = File(args[1]);
  marker.writeAsStringSync('$pid\n');
  var count = 0;
  await for (final command
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    marker.writeAsStringSync('$command\n', mode: FileMode.append);
    if (mode == 'hang') {
      // Deliberately ignore EOF and graceful requests to exercise forced cleanup.
      await Completer<void>().future;
      return;
    }
    if (mode == 'crash') exit(7);
    if (mode == 'flood') {
      stdout.write('x' * (300 * 1024));
      await stdout.flush();
      continue;
    }
    if (mode == 'malformed') {
      stdout.writeln('CIE_OBSERVER_JSON={');
      continue;
    }
    count++;
    stdout.writeln(
      'CIE_OBSERVER_JSON=${jsonEncode({
        'ok': true,
        'readers': count.isEven ? [] : [
                {'name': 'Synthetic reader', 'present': true, 'isCie': true, 'cardId': 'TEST'},
              ],
        'pid': pid,
      })}',
    );
  }
}
