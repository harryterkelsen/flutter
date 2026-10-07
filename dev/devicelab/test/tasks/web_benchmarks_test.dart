import 'dart:io';

import 'package:flutter_devicelab/framework/framework.dart';
import 'package:flutter_devicelab/tasks/web_benchmarks.dart';
import 'package:test/test.dart';

void main() {
  group('BenchmarkFilter', () {
    final List<String> allBenchmarks = <String>[
      'draw_rect',
      'bench_card',
      'foo_bar',
      'bench_card_infinite_scroll',
    ];

    test('exact matching of single and multiple target benchmarks', () {
      final BenchmarkFilter filter = BenchmarkFilter(targetBenchmarks: <String>['draw_rect', 'bench_card']);
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect', 'bench_card']);
    });

    test('trimming whitespace in target benchmarks', () {
      final BenchmarkFilter filter = BenchmarkFilter(targetBenchmarks: <String>[' draw_rect ', 'bench_card ']);
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect', 'bench_card']);
    });

    test('regex pattern filtering', () {
      final BenchmarkFilter filter = BenchmarkFilter(filterPattern: r'^draw_');
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect']);
    });

    test('strict fail-fast error when target benchmark is missing/misspelled', () {
      final BenchmarkFilter filter = BenchmarkFilter(targetBenchmarks: <String>['draw_rect', 'draw_rext']);
      expect(
        () => filter.filter(allBenchmarks),
        throwsA(isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('Unrecognized target benchmark(s): [draw_rext]'),
        )),
      );
    });

    test('error when regex matches zero benchmarks', () {
      final BenchmarkFilter filter = BenchmarkFilter(filterPattern: r'^non_existent_');
      expect(
        () => filter.filter(allBenchmarks),
        throwsA(isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('No benchmarks matched the requested filter.'),
        )),
      );
    });

    test('eager validation error when filterPattern is an invalid regex', () {
      expect(
        () => BenchmarkFilter(filterPattern: '['),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('processBenchmarkProfiles', () {
    final WebBenchmarkOptions options = (
      useWasm: false,
      forceSingleThreadedSkwasm: false,
      useDdc: false,
      withHotReload: false,
      buildMode: 'profile',
    );

    test('empty profiles list returns TaskResult.failure', () {
      final TaskResult result = processBenchmarkProfiles(<Map<String, dynamic>>[], options);
      expect(result.succeeded, isFalse);
      expect(result.message, 'No benchmark profiles were collected.');
    });

    test('missing or empty benchmark name returns TaskResult.failure', () {
      final TaskResult result = processBenchmarkProfiles(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': '',
          'scoreKeys': <String>['frame_build_times'],
        },
      ], options);
      expect(result.succeeded, isFalse);
      expect(result.message, 'Benchmark name is empty');
    });

    test('empty scoreKeys returns TaskResult.failure', () {
      final TaskResult result = processBenchmarkProfiles(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'draw_rect',
          'scoreKeys': <String>[],
        },
      ], options);
      expect(result.succeeded, isFalse);
      expect(result.message, 'No score keys in benchmark "draw_rect"');
    });

    test('successful profile transformation into TaskResult.success', () {
      final TaskResult result = processBenchmarkProfiles(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'draw_rect',
          'scoreKeys': <String>['frame_build_times'],
          'frame_build_times': 123.4,
        },
      ], options);
      expect(result.succeeded, isTrue);
      expect(result.benchmarkScoreKeys, <String>['draw_rect.canvaskit.frame_build_times']);
      expect(result.data, <String, dynamic>{
        'draw_rect.canvaskit.frame_build_times': 123.4,
      });
    });

    test('successful profile transformation into TaskResult.success (Wasm Skwasm)', () {
      final TaskResult result = processBenchmarkProfiles(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'draw_rect',
            'scoreKeys': <String>['frame_build_times'],
            'frame_build_times': 123.4,
          },
        ],
        (
          useWasm: true,
          forceSingleThreadedSkwasm: false,
          useDdc: false,
          withHotReload: false,
          buildMode: 'profile',
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.benchmarkScoreKeys, <String>['draw_rect.skwasm.frame_build_times']);
      expect(result.data, <String, dynamic>{
        'draw_rect.skwasm.frame_build_times': 123.4,
      });
    });
  });

  group('runWebBenchmarkFromArgs / env overrides', () {
    final WebBenchmarkOptions options = (
      useWasm: false,
      forceSingleThreadedSkwasm: false,
      useDdc: false,
      withHotReload: false,
      buildMode: 'profile',
    );

    test('tolerance to unexpected runner arguments or parse exceptions', () async {
      final TaskResult result = await runWebBenchmarkFromArgs(options, <String>['--invalid-flag']);
      expect(result.succeeded, isFalse);
      expect(result.message, contains('Could not find an option named "invalid-flag".'));
    });
  });
}
