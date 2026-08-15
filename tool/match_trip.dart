// Runs the quill corridor-matching pipeline against a legacy Ring-Ring
// export from the command line, without building the app.
//
// Usage:
//   dart run tool/match_trip.dart --trip <trip.json> --registry <registry.json>
import 'dart:convert';
import 'dart:io';

import 'package:ringring_logger/legacy/legacy_trip_format.dart';
import 'package:ringring_logger/quill/claims.dart';
import 'package:ringring_logger/quill/matcher.dart';
import 'package:ringring_logger/quill/registry.dart';

void main(List<String> args) {
  final options = _parseArgs(args);

  final points = parseLegacyDetails(File(options['trip']!).readAsStringSync());
  final registry = Registry.parse(File(options['registry']!).readAsStringSync());

  final traversals = matchTrip(points, registry);
  final claims = deriveClaims(traversals, registry);

  const encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(claims.map((c) => c.toJson()).toList()));
  stdout.writeln(
    '${points.length} points -> ${traversals.length} traversals -> ${claims.length} claims',
  );
}

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--trip') result['trip'] = args[i + 1];
    if (args[i] == '--registry') result['registry'] = args[i + 1];
  }
  if (result['trip'] == null || result['registry'] == null) {
    stderr.writeln(
      'Usage: dart run tool/match_trip.dart --trip <trip.json> --registry <registry.json>',
    );
    exit(64);
  }
  return result;
}
