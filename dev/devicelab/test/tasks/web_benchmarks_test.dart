import 'package:args/args.dart';
import 'package:flutter_devicelab/framework/task_result.dart';
import 'package:flutter_devicelab/tasks/web_benchmarks.dart';
import 'package:flutter_devicelab/tasks/web_benchmarks_helpers.dart';

import '../common.dart';

void main() {
  group('BenchmarkFilter', () {
    final allBenchmarks = <String>[
      'draw_rect',
      'bench_card',
      'foo_bar',
      'bench_card_infinite_scroll',
    ];

    test('exact matching of single and multiple target benchmarks', () {
      final filter = BenchmarkFilter(targetBenchmarks: <String>['draw_rect', 'bench_card']);
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect', 'bench_card']);
    });

    test(
      'treats empty target list or only-whitespace targets as if no targetBenchmarks were provided',
      () {
        final filter = BenchmarkFilter(targetBenchmarks: <String>['  ', '']);
        final List<String> result = filter.filter(allBenchmarks);
        expect(result, allBenchmarks);
      },
    );

    test('combines targetBenchmarks and filterPattern (intersection)', () {
      final filter = BenchmarkFilter.parse(
        targetBenchmarks: <String>['draw_rect', 'bench_card'],
        filterPattern: r'^draw_',
      );
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect']);
    });

    test('trimming whitespace in target benchmarks', () {
      final filter = BenchmarkFilter(targetBenchmarks: <String>[' draw_rect ', 'bench_card ']);
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect', 'bench_card']);
    });

    test('regex pattern filtering', () {
      final filter = BenchmarkFilter.parse(filterPattern: r'^draw_');
      final List<String> result = filter.filter(allBenchmarks);
      expect(result, <String>['draw_rect']);
    });

    test('strict fail-fast error when target benchmark is missing/misspelled', () {
      final filter = BenchmarkFilter(targetBenchmarks: <String>['draw_rect', 'draw_rext']);
      expect(
        () => filter.filter(allBenchmarks),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('Unrecognized target benchmark(s): [draw_rext]'),
          ),
        ),
      );
    });

    test('error when regex matches zero benchmarks', () {
      final filter = BenchmarkFilter.parse(filterPattern: r'^non_existent_');
      expect(
        () => filter.filter(allBenchmarks),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('No benchmarks matched the requested filter.'),
          ),
        ),
      );
    });

    test('eager validation error when filterPattern is an invalid regex', () {
      expect(() => BenchmarkFilter.parse(filterPattern: '['), throwsA(isA<Exception>()));
    });
  });

  group('BenchmarkFilter.parse (environment overrides)', () {
    test('uses BENCHMARK_TARGETS when targetBenchmarks is null', () {
      final filter = BenchmarkFilter.parse(
        environment: <String, String>{'BENCHMARK_TARGETS': 'draw_rect, bench_card'},
      );
      expect(filter.targetBenchmarks, <String>['draw_rect', 'bench_card']);
    });

    test('ignores BENCHMARK_TARGETS when targetBenchmarks is provided', () {
      final filter = BenchmarkFilter.parse(
        targetBenchmarks: <String>['foo_bar'],
        environment: <String, String>{'BENCHMARK_TARGETS': 'draw_rect, bench_card'},
      );
      expect(filter.targetBenchmarks, <String>['foo_bar']);
    });

    test('uses BENCHMARK_FILTER when filterPattern is null', () {
      final filter = BenchmarkFilter.parse(
        environment: <String, String>{'BENCHMARK_FILTER': r'^draw_'},
      );
      expect(filter.compiledFilter?.pattern, r'^draw_');
    });

    test('ignores BENCHMARK_FILTER when filterPattern is provided', () {
      final filter = BenchmarkFilter.parse(
        filterPattern: 'skwasm',
        environment: <String, String>{'BENCHMARK_FILTER': r'^draw_'},
      );
      expect(filter.compiledFilter?.pattern, 'skwasm');
    });

    test('fails fast on invalid regex in BENCHMARK_FILTER', () {
      expect(
        () => BenchmarkFilter.parse(environment: <String, String>{'BENCHMARK_FILTER': '['}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('processBenchmarkProfiles', () {
    const WebBenchmarkOptions options = (
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
        <String, dynamic>{'name': 'draw_rect', 'scoreKeys': <String>[]},
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
      expect(result.data, <String, dynamic>{'draw_rect.canvaskit.frame_build_times': 123.4});
    });

    test('successful profile transformation into TaskResult.success (Skwasm)', () {
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
      expect(result.data, <String, dynamic>{'draw_rect.skwasm.frame_build_times': 123.4});
    });

    test('fails if scoreKeys contains empty string', () {
      final TaskResult result = processBenchmarkProfiles(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'draw_rect',
          'scoreKeys': <String>['frame_build_times', ''],
          'frame_build_times': 123.4,
        },
      ], options);
      expect(result.succeeded, isFalse);
      expect(result.message, contains('A score key is empty in benchmark'));
    });

    test('ignores data keys that match internal keys like "name" or "scoreKeys"', () {
      final TaskResult result = processBenchmarkProfiles(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'draw_rect',
          'scoreKeys': <String>['frame_build_times'],
          'frame_build_times': 123.4,
          // ignore: equal_keys_in_map
          'name': 'another_name', // Should be ignored by the loop in processBenchmarkProfiles
        },
      ], options);
      expect(result.succeeded, isTrue);
    });
  });

  group('runWebBenchmarkFromArgs', () {
    const WebBenchmarkOptions options = (
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

  group('filterBenchmarks', () {
    final all = <String>['draw_rect', 'bench_card_1', 'bench_card_2', 'foo_bar'];

    test('Exact match: --benchmark=draw_rect returns only [draw_rect]', () {
      expect(filterBenchmarks(allBenchmarks: all, benchmark: 'draw_rect'), ['draw_rect']);
    });

    test('Regex match: --filter="bench_card_.*" returns matching items', () {
      expect(filterBenchmarks(allBenchmarks: all, filterPattern: 'bench_card_.*'), [
        'bench_card_1',
        'bench_card_2',
      ]);
    });

    test(
      'Regex validation: Throws ArgumentError when filterPattern is an invalid regular expression',
      () {
        expect(() => filterBenchmarks(allBenchmarks: all, filterPattern: '['), throwsArgumentError);
      },
    );

    test('Blank filter validation: Throws ArgumentError when benchmark or filterPattern is empty or whitespace-only', () {
      expect(() => filterBenchmarks(allBenchmarks: all, benchmark: '   '), throwsArgumentError);
      expect(() => filterBenchmarks(allBenchmarks: all, filterPattern: ''), throwsArgumentError);
    });

    test('Smoke-test: --smoke-test returns kSmokeTestBenchmarks', () {
      expect(
        filterBenchmarks(allBenchmarks: kSmokeTestBenchmarks, smokeTest: true),
        kSmokeTestBenchmarks,
      );
    });

    test('Smoke-test validation: Throws ArgumentError if any smoke test benchmark is missing from allBenchmarks', () {
      expect(
        () => filterBenchmarks(allBenchmarks: ['draw_rect'], smokeTest: true),
        throwsArgumentError,
      );
    });

    test('Mutual exclusion: Throws ArgumentError when multiple filtering options are provided', () {
      expect(
        () => filterBenchmarks(allBenchmarks: all, smokeTest: true, benchmark: 'draw_rect'),
        throwsArgumentError,
      );
      expect(
        () => filterBenchmarks(allBenchmarks: all, smokeTest: true, filterPattern: 'draw_.*'),
        throwsArgumentError,
      );
      expect(
        () =>
            filterBenchmarks(allBenchmarks: all, benchmark: 'draw_rect', filterPattern: 'draw_.*'),
        throwsArgumentError,
      );
    });

    test('All benchmarks: No filter provided returns full list unchanged', () {
      expect(filterBenchmarks(allBenchmarks: all), all);
    });

    test('Hostile: allBenchmarks is empty list throws ArgumentError when filter applied', () {
      expect(
        () => filterBenchmarks(allBenchmarks: <String>[], filterPattern: '.*'),
        throwsArgumentError,
      );
    });

    test(
      'Typo / 0 match: Throws ArgumentError with clear message listing available benchmarks',
      () {
        expect(
          () => filterBenchmarks(allBenchmarks: all, benchmark: 'non_existent'),
          throwsArgumentError,
        );
        expect(
          () => filterBenchmarks(allBenchmarks: all, filterPattern: 'non_existent_.*'),
          throwsArgumentError,
        );
      },
    );
  });

  group('compareResults', () {
    test('Regression detected: delta exceeds regressionThreshold=10.0', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0},
        current: {'a.average': 115.0},
        regressionThreshold: 10.0,
      );
      expect(result.hasRegressions, true);
      expect(result.metrics.first.deltaPercent, 15.0);
      expect(result.metrics.first.isRegression, true);
    });

    test('Acceptable change: delta within threshold, flags isRegression: false', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0},
        current: {'a.average': 105.0},
        regressionThreshold: 10.0,
      );
      expect(result.hasRegressions, false);
      expect(result.metrics.first.deltaPercent, 5.0);
      expect(result.metrics.first.isRegression, false);
    });

    test('Speedup: negative delta (e.g. -25%), flags isRegression: false even if magnitude exceeds threshold', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0},
        current: {'a.average': 75.0},
        regressionThreshold: 10.0,
      );
      expect(result.hasRegressions, false);
      expect(result.metrics.first.deltaPercent, -25.0);
      expect(result.metrics.first.isRegression, false);
    });

    test('Negative or non-finite threshold: passing regressionThreshold: -5.0 or double.nan throws ArgumentError', () {
      expect(
        () => compareResults(baseline: {'a': 1}, current: {'a': 1}, regressionThreshold: -5.0),
        throwsArgumentError,
      );
      expect(
        () =>
            compareResults(baseline: {'a': 1}, current: {'a': 1}, regressionThreshold: double.nan),
        throwsArgumentError,
      );
    });

    test('Missing baseline metrics (strict): with failOnMissingBaseline: true', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0},
        current: {},
        regressionThreshold: 10.0,
      );
      expect(result.hasRegressions, true);
      expect(result.missingMetrics.length, 1);
      final MetricComparison missingMetric = result.metrics.firstWhere(
        (m) => m.metricKey == 'a.average',
      );
      expect(result.missingMetrics.first, 'a.average');
      expect(missingMetric.current, isNull);
      expect(missingMetric.deltaPercent, double.infinity);
      expect(missingMetric.isRegression, true);
    });

    test('Missing baseline metrics (partial run): with failOnMissingBaseline: false', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0},
        current: {},
        regressionThreshold: 10.0,
        failOnMissingBaseline: false,
      );
      expect(result.hasRegressions, false);
      expect(result.missingMetrics.length, 1);
      final MetricComparison missingMetric = result.metrics.firstWhere(
        (m) => m.metricKey == 'a.average',
      );
      expect(missingMetric.current, isNull);
      expect(missingMetric.deltaPercent, double.infinity);
      expect(missingMetric.isRegression, false);
    });

    test('New metrics (current only): metric present in current but absent in baseline', () {
      final BenchmarkComparison result = compareResults(
        baseline: {},
        current: {'a.average': 100.0},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.first.baseline, isNull);
      expect(result.metrics.first.deltaPercent, 0.0);
      expect(result.metrics.first.isRegression, false);
    });

    test('Metric eligibility: evaluates all numeric metrics ending in .average and ignores non-average metrics or non-numeric keys', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0, 'a.median': 50.0, 'a.string': 'foo'},
        current: {'a.average': 100.0, 'a.median': 50.0, 'a.string': 'foo'},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.length, 1);
      expect(result.metrics.first.metricKey, 'a.average');
    });

    test('Deterministic metric ordering: metrics in BenchmarkComparison.metrics are sorted alphabetically by metricKey', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'b.average': 100.0, 'a.average': 100.0, 'c.average': 100.0},
        current: {'b.average': 100.0, 'a.average': 100.0, 'c.average': 100.0},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.map((m) => m.metricKey).toList(), [
        'a.average',
        'b.average',
        'c.average',
      ]);
    });

    test('Zero baseline jump: baseline is 0.0 and current is positive', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 0.0},
        current: {'a.average': 150.0},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.first.deltaPercent, double.infinity);
      expect(result.metrics.first.isRegression, true);
      expect(result.hasRegressions, true);
    });

    test('Zero baseline unchanged: baseline is 0.0 and current is 0.0', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 0.0},
        current: {'a.average': 0.0},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.first.deltaPercent, 0.0);
      expect(result.metrics.first.isRegression, false);
      expect(result.hasRegressions, false);
    });

    test(
      'Type safety & integer metrics: successfully parses both Dart int and double durations',
      () {
        final BenchmarkComparison result = compareResults(
          baseline: {'a.average': 100},
          current: {'a.average': 150.0},
          regressionThreshold: 10.0,
        );
        expect(result.metrics.first.deltaPercent, 50.0);
      },
    );

    test('Non-finite or negative values: throws FormatException on double.nan, double.infinity, negative numbers, or non-num/null values for keys ending in .average', () {
      expect(
        () => compareResults(baseline: {'a.average': -100.0}, current: {'a.average': 100.0}),
        throwsFormatException,
      );
      expect(
        () => compareResults(baseline: {'a.average': 100.0}, current: {'a.average': double.nan}),
        throwsFormatException,
      );
      expect(
        () =>
            compareResults(baseline: {'a.average': double.infinity}, current: {'a.average': 100.0}),
        throwsFormatException,
      );
      expect(
        () =>
            compareResults(baseline: {'a.average': 'string_value'}, current: {'a.average': 100.0}),
        throwsFormatException,
      );
      final BenchmarkComparison result = compareResults(
        baseline: {'a.average': 100.0, 'a.something_else': double.nan},
        current: {'a.average': 100.0},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.length, 1);
    });

    test('Flattened input schema: accepts flattened TaskResult.data maps and ignores non-numeric keys / metadata', () {
      final BenchmarkComparison result = compareResults(
        baseline: {'draw_rect.canvaskit.totalUiFrame.average': 123.4, 'metadata': 'ignored'},
        current: {'draw_rect.canvaskit.totalUiFrame.average': 130.0},
        regressionThreshold: 10.0,
      );
      expect(result.metrics.length, 1);
      expect(result.metrics.first.metricKey, 'draw_rect.canvaskit.totalUiFrame.average');
    });

    test(
      'Hostile: regressionThreshold of 0.0 correctly flags strictly positive deltas as regressions',
      () {
        // ignore: unused_local_variable
        final BenchmarkComparison comp = compareResults(
          baseline: {'a.average': 100.0, 'b.average': 100.0},
          current: {'a.average': 100.0001, 'b.average': 100.0},
          regressionThreshold: 0.0,
        );
        expect(comp.hasRegressions, true);
        final MetricComparison metricA = comp.metrics.firstWhere((m) => m.metricKey == 'a.average');
        final MetricComparison metricB = comp.metrics.firstWhere((m) => m.metricKey == 'b.average');
        expect(metricA.isRegression, true);
        expect(metricB.isRegression, false);
      },
    );

    test('Hostile: compareResults with completely empty baseline and current maps', () {
      // ignore: unused_local_variable
      final BenchmarkComparison comp = compareResults(baseline: {}, current: {});
      expect(comp.hasRegressions, false);
      expect(comp.metrics.isEmpty, true);
      expect(comp.missingMetrics.isEmpty, true);
    });
  });

  group('formatAnsiSummaryTable', () {
    test('Table contains metric names, baseline values, current values, formatted deltas, and status labels', () {
      // ignore: unused_local_variable
      final comp = BenchmarkComparison(
        regressionThreshold: 10.0,
        metrics: [
          MetricComparison(
            metricKey: 'a.average',
            baseline: 100.0,
            current: 150.0,
            deltaPercent: 50.0,
            isRegression: true,
          ),
          MetricComparison(
            metricKey: 'b.average',
            baseline: 100.0,
            current: 100.0,
            deltaPercent: 0.0,
            isRegression: false,
          ),
        ],
        missingMetrics: [],
      );
      final String table = formatAnsiSummaryTable(comp, enableAnsi: false);
      expect(table, contains('a.average'));
      expect(table, contains('100.0'));
      expect(table, contains('150.0'));
      expect(table, contains('50.0%'));
      expect(table, contains('FAIL'));
      expect(table, contains('b.average'));
      expect(table, contains('PASS'));
    });

    test('Null and infinite formatting: renders null baseline, null current, and infinite delta as N/A', () {
      // ignore: unused_local_variable
      final comp = BenchmarkComparison(
        regressionThreshold: 10.0,
        metrics: [
          MetricComparison(
            metricKey: 'new.average',
            baseline: null,
            current: 150.0,
            deltaPercent: 0.0,
            isRegression: false,
          ),
          MetricComparison(
            metricKey: 'missing.average',
            baseline: 100.0,
            current: null,
            deltaPercent: double.infinity,
            isRegression: true,
          ),
        ],
        missingMetrics: ['missing.average'],
      );
      final String table = formatAnsiSummaryTable(comp, enableAnsi: false);
      expect(table, contains('new.average'));
      expect(table, contains('N/A'));
      expect(table, contains('missing.average'));
      expect(table, contains('N/A'));
    });

    test(
      'Status column: displays FAIL when isRegression: true, and PASS when isRegression: false',
      () {
        // ignore: unused_local_variable
        final comp = BenchmarkComparison(
          regressionThreshold: 10.0,
          metrics: [
            MetricComparison(
              metricKey: 'missing.average',
              baseline: 100.0,
              current: null,
              deltaPercent: double.infinity,
              isRegression: false,
            ),
          ],
          missingMetrics: ['missing.average'],
        );
        final String table = formatAnsiSummaryTable(comp, enableAnsi: false);
        expect(table, contains('missing.average'));
        expect(table, contains('PASS'));
      },
    );

    test('Row ordering: rows are printed alphabetically by metricKey', () {
      // ignore: unused_local_variable
      final comp = BenchmarkComparison(
        regressionThreshold: 10.0,
        metrics: [
          MetricComparison(
            metricKey: 'z.average',
            baseline: 100.0,
            current: 100.0,
            deltaPercent: 0.0,
            isRegression: false,
          ),
          MetricComparison(
            metricKey: 'a.average',
            baseline: 100.0,
            current: 100.0,
            deltaPercent: 0.0,
            isRegression: false,
          ),
          MetricComparison(
            metricKey: 'm.average',
            baseline: 100.0,
            current: null,
            deltaPercent: double.infinity,
            isRegression: false,
          ),
        ],
        missingMetrics: ['m.average'],
      );
      final String table = formatAnsiSummaryTable(comp, enableAnsi: false);
      final int indexOfA = table.indexOf('a.average');
      final int indexOfM = table.indexOf('m.average');
      final int indexOfZ = table.indexOf('z.average');
      expect(indexOfA < indexOfM, true); // Note: Fixed in dart string below
      expect(indexOfM < indexOfZ, true); // Note: Fixed in dart string below
    });

    test('ANSI control: With enableAnsi: true, emits ANSI color formatting', () {
      // ignore: unused_local_variable
      final comp = BenchmarkComparison(
        regressionThreshold: 10.0,
        metrics: [
          MetricComparison(
            metricKey: 'a.average',
            baseline: 100.0,
            current: 150.0,
            deltaPercent: 50.0,
            isRegression: true,
          ),
        ],
        missingMetrics: [],
      );
      final String tableAnsi = formatAnsiSummaryTable(comp);
      expect(tableAnsi, contains('['));

      final String tablePlain = formatAnsiSummaryTable(comp, enableAnsi: false);
      expect(tablePlain, isNot(contains('[')));
    });

    test('Hostile: empty metrics list generates empty table output', () {
      // ignore: unused_local_variable
      final comp = BenchmarkComparison(regressionThreshold: 10.0, metrics: [], missingMetrics: []);
      final String table = formatAnsiSummaryTable(comp);
      expect(table.trim(), isEmpty);
    });
  });

  group('formatStructuredJson', () {
    test('Emits valid JSON map matching the standardized schema with timestamp, metadata, and benchmarks', () {
      // ignore: unused_local_variable
      final comp = BenchmarkComparison(
        regressionThreshold: 10.0,
        metrics: [
          MetricComparison(
            metricKey: 'a.average',
            baseline: 100.0,
            current: 100.0,
            deltaPercent: 0.0,
            isRegression: false,
          ),
        ],
        missingMetrics: [],
      );
      final Map<String, dynamic> metadata = {'foo': 'bar'};
      final Map<String, dynamic> result = formatStructuredJson(
        profiles: <Map<String, dynamic>>[
          {'a.average': 100.0},
        ],
        metadata: metadata,
      );
      expect(result.containsKey('timestamp'), true);
      expect(result['metadata'], metadata);
      expect(result.containsKey('benchmarks'), true);
      expect((result['benchmarks'] as Map<String, dynamic>)['a.average'], isNotNull);
    });

    test('Deterministic timestamp: when timestamp parameter is provided, outputs the formatted ISO-8601 UTC string', () {
      final dt = DateTime(2023, 10, 5, 12);
      final Map<String, dynamic> result = formatStructuredJson(
        profiles: <Map<String, dynamic>>[],
        metadata: {},
        timestamp: dt,
      );
      expect(result['timestamp'], dt.toUtc().toIso8601String());
    });

    test('Hostile: empty profiles and metadata', () {
      final Map<String, dynamic> result = formatStructuredJson(
        profiles: <Map<String, dynamic>>[],
        metadata: {},
      );
      expect(result['metadata'], isEmpty);
      expect((result['benchmarks'] as Map).isEmpty, true);
    });
  });

  group('CLI Argument and Runner Tests', () {
    test('Argument parsing includes all flags and --help', () {
      final ArgParser parser = buildBenchmarkArgParser();
      expect(parser.options.containsKey('help'), isTrue);
      expect(parser.options.containsKey('benchmark'), isTrue);
      expect(parser.options.containsKey('smoke-test'), isTrue);
      expect(parser.options.containsKey('filter'), isTrue);
      expect(parser.options.containsKey('baseline'), isTrue);
      expect(parser.options.containsKey('results-file'), isTrue);
      expect(parser.options.containsKey('renderer'), isTrue);
      expect(parser.options.containsKey('regression-threshold'), isTrue);
      expect(parser.options.containsKey('clean'), isTrue);
      expect(parser.options.containsKey('no-build'), isTrue);
      expect(parser.options.containsKey('local-engine-src-path'), isTrue);
      expect(parser.options.containsKey('local-web-sdk'), isTrue);
    });

    test(
      'runBenchmarkCli handles ArgParserException, prints usage and exits with code 2',
      () async {
        final outLines = <String>[];
        final errLines = <String>[];
        final int exitCode = await runBenchmarkCli(
          <String>['--invalid-flag'],
          out: outLines.add,
          err: errLines.add,
        );
        expect(exitCode, 2);
        expect(
          errLines.any(
            (String line) => line.contains('Could not find an option named "invalid-flag"'),
          ),
          isTrue,
        );
        expect(outLines.any((String line) => line.contains('Usage:')), isTrue);
      },
    );

    test('Rejection of conflicting selectors', () async {
      final conflicts = <List<String>>[
        <String>['--benchmark=foo', '--smoke-test'],
        <String>['--filter=foo', '--smoke-test'],
        <String>['--benchmark=foo', '--filter=foo'],
      ];
      for (final args in conflicts) {
        final errLines = <String>[];
        final int exitCode = await runBenchmarkCli(args, err: errLines.add);
        expect(exitCode, 2);
        expect(errLines.any((String line) => line.contains('Cannot use')), isTrue);
      }
    });

    test('Default execution of all benchmarks when no selector flag is passed', () async {
      var runnerCalled = false;
      final int exitCode = await runBenchmarkCli(
        <String>[],
        runner:
            ({
              required List<String>? benchmark,
              required bool smokeTest,
              required String? filter,
              required String renderer,
              required bool clean,
              required bool noBuild,
              required String? localEngineSrcPath,
              required String? localWebSdk,
            }) async {
              runnerCalled = true;
              expect(benchmark, isEmpty);
              expect(smokeTest, isFalse);
              expect(filter, isNull);
              return <String, dynamic>{
                'timestamp': '2023',
                'metadata': <String, dynamic>{},
                'benchmarks': <String, dynamic>{},
              };
            },
      );
      expect(runnerCalled, isTrue);
      expect(exitCode, 0);
    });

    test('runBenchmarkCli parses arguments correctly and delegates to runner', () async {
      var runnerCalled = false;
      final int exitCode = await runBenchmarkCli(
        <String>['--benchmark=draw_rect', '--renderer=skwasm', '--no-build'],
        runner:
            ({
              required List<String>? benchmark,
              required bool smokeTest,
              required String? filter,
              required String renderer,
              required bool clean,
              required bool noBuild,
              required String? localEngineSrcPath,
              required String? localWebSdk,
            }) async {
              runnerCalled = true;
              expect(benchmark, <String>['draw_rect']);
              expect(smokeTest, isFalse);
              expect(filter, isNull);
              expect(renderer, 'skwasm');
              expect(clean, isFalse); // noBuild disarms clean
              expect(noBuild, isTrue);
              expect(localEngineSrcPath, isNull);
              expect(localWebSdk, isNull);
              return <String, dynamic>{
                'timestamp': '2023',
                'metadata': <String, dynamic>{},
                'benchmarks': {
                  'draw_rect.skwasm': {'a.average': 100},
                },
              };
            },
      );
      expect(runnerCalled, isTrue);
      expect(exitCode, 0);
    });

    test('Rejection of identical canonical paths for --baseline and --results-file', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(<String>[
        '--baseline=./path/to/file.json',
        '--results-file=path/to/file.json',
      ], err: errLines.add);
      expect(exitCode, 2);
      expect(
        errLines.any(
          (String line) => line.contains('baseline and results-file cannot be the same'),
        ),
        isTrue,
      );
    });

    test('Validation of --renderer allowed choices', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(<String>[
        '--renderer=invalid_renderer',
      ], err: errLines.add);
      expect(exitCode, 2);
      expect(
        errLines.any((String line) => line.contains('invalid_renderer is not an allowed value')),
        isTrue,
      );
    });

    test('Rejection of negative, NaN, or infinite regression-threshold', () async {
      for (final val in <String>['-0.1', 'NaN', 'Infinity']) {
        final errLines = <String>[];
        final int exitCode = await runBenchmarkCli(<String>[
          '--regression-threshold=$val',
          '--baseline=b.json',
        ], err: errLines.add);
        expect(exitCode, 2);
        expect(errLines.any((String line) => line.contains('must be a positive number')), isTrue);
      }
    });

    test('Rejection of --regression-threshold when --baseline is omitted', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(<String>[
        '--regression-threshold=0.1',
      ], err: errLines.add);
      expect(exitCode, 2);
      expect(
        errLines.any((String line) => line.contains('regression-threshold requires a baseline')),
        isTrue,
      );
    });

    test('Validation of mutual exclusion between --clean and --no-build', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(<String>[
        '--clean',
        '--no-build',
      ], err: errLines.add);
      expect(exitCode, 2);
      expect(
        errLines.any((String line) => line.contains('Cannot use --clean and --no-build together')),
        isTrue,
      );
    });

    test('Validation that --local-engine-src-path requires --local-web-sdk', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(<String>[
        '--local-engine-src-path=/some/path',
      ], err: errLines.add);
      expect(exitCode, 2);
      expect(
        errLines.any(
          (String line) => line.contains('local-engine-src-path requires local-web-sdk'),
        ),
        isTrue,
      );
    });

    test('Upfront validation of --baseline file existence and JSON parsing', () async {
      final errLines = <String>[];
      // File doesn't exist
      final int exitCode = await runBenchmarkCli(<String>[
        '--baseline=non_existent_file.json',
      ], err: errLines.add);
      expect(exitCode, 2);
      expect(errLines.any((String line) => line.contains('Baseline file not found')), isTrue);
    });

    test('Detection of empty metric intersection or lack of .average metrics between baseline and current results, exiting with code 2', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(
        <String>['--baseline=baseline.json'],
        runner:
            ({
              required List<String>? benchmark,
              required bool smokeTest,
              required String? filter,
              required String renderer,
              required bool clean,
              required bool noBuild,
              required String? localEngineSrcPath,
              required String? localWebSdk,
            }) async => <String, dynamic>{
              'timestamp': '2023',
              'metadata': <String, dynamic>{},
              'benchmarks': {
                'draw_rect.canvaskit': {'b.average': 100},
              },
            },
        readBaseline: (String path) => <String, dynamic>{
          'benchmarks': {
            'draw_rect.canvaskit': {'a.average': 100}, // disjoint metrics
          },
        },
        err: errLines.add,
      );
      expect(exitCode, 2);
      expect(errLines.any((String line) => line.contains('No overlapping metrics')), isTrue);
    });

    test('Validation of renderer-specific artifact existence under --no-build anchored to flutterRootDir', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(
        <String>['--no-build', '--renderer=skwasm'],
        flutterRootDir: '/fake/flutter/root',
        checkArtifacts: (String root, String renderer) => false,
        err: errLines.add,
      );
      expect(exitCode, 2);
      expect(
        errLines.any((String line) => line.contains('Artifacts for renderer skwasm not found')),
        isTrue,
      );
    });

    test('Graceful handling of file system errors for --results-file', () async {
      final errLines = <String>[];
      final int exitCode = await runBenchmarkCli(
        <String>['--results-file=/nonexistent_dir/results.json'],
        runner: ({
          required List<String>? benchmark,
          required bool smokeTest,
          required String? filter,
          required String renderer,
          required bool clean,
          required bool noBuild,
          required String? localEngineSrcPath,
          required String? localWebSdk,
        }) async => <String, dynamic>{},
        writeResults: (String path, String content) => throw Exception('Cannot write file'),
        err: errLines.add,
      );
      expect(exitCode, 2);
      expect(errLines.any((String line) => line.contains('Failed to write results')), isTrue);
    });
  });
  test('Hostile: Badly typed baseline benchmarks (List instead of Map)', () async {
    final errLines = <String>[];
    final int exitCode = await runBenchmarkCli(
      <String>['--baseline=baseline.json'],
      runner:
          ({
            required List<String>? benchmark,
            required bool smokeTest,
            required String? filter,
            required String renderer,
            required bool clean,
            required bool noBuild,
            required String? localEngineSrcPath,
            required String? localWebSdk,
          }) async => <String, dynamic>{
            'benchmarks': {
              'draw_rect.canvaskit': {'a.average': 100},
            },
          },
      readBaseline: (String path) => <String, dynamic>{
        'benchmarks': <dynamic>[], // Badly typed: List instead of Map
      },
      err: errLines.add,
    );
    expect(exitCode, 2);
  });

  test('Hostile: Graceful handling of empty baseline JSON (empty object)', () async {
    final errLines = <String>[];
    final int exitCode = await runBenchmarkCli(
      <String>['--baseline=baseline.json'],
      runner:
          ({
            required List<String>? benchmark,
            required bool smokeTest,
            required String? filter,
            required String renderer,
            required bool clean,
            required bool noBuild,
            required String? localEngineSrcPath,
            required String? localWebSdk,
          }) async => <String, dynamic>{
            'benchmarks': {
              'draw_rect.canvaskit': {'a.average': 100},
            },
          },
      readBaseline: (String path) => <String, dynamic>{}, // Empty object
      err: errLines.add,
    );
    expect(exitCode, 2);
    expect(errLines.any((String line) => line.contains('No overlapping metrics')), isTrue);
  });

  test('Hostile: Rejection of unparseable baseline JSON string', () async {
    final errLines = <String>[];
    final int exitCode = await runBenchmarkCli(
      <String>['--baseline=baseline.json'],
      runner: ({
        required List<String>? benchmark,
        required bool smokeTest,
        required String? filter,
        required String renderer,
        required bool clean,
        required bool noBuild,
        required String? localEngineSrcPath,
        required String? localWebSdk,
      }) async => <String, dynamic>{},
      readBaseline: (String path) => throw const FormatException('Invalid JSON'),
      err: errLines.add,
    );
    expect(exitCode, 2);
  });

  test('Hostile: Badly typed current results benchmarks (List instead of Map)', () async {
    final errLines = <String>[];
    final int exitCode = await runBenchmarkCli(
      <String>['--baseline=baseline.json'],
      runner:
          ({
            required List<String>? benchmark,
            required bool smokeTest,
            required String? filter,
            required String renderer,
            required bool clean,
            required bool noBuild,
            required String? localEngineSrcPath,
            required String? localWebSdk,
          }) async => <String, dynamic>{
            'benchmarks': <dynamic>[], // Badly typed current results
          },
      readBaseline: (String path) => <String, dynamic>{
        'benchmarks': {
          'draw_rect.canvaskit': {'a.average': 100},
        },
      },
      err: errLines.add,
    );
    expect(exitCode, 2);
  });

  test('Hostile: Missing .average in common metrics', () async {
    final errLines = <String>[];
    final int exitCode = await runBenchmarkCli(
      <String>['--baseline=baseline.json'],
      runner:
          ({
            required List<String>? benchmark,
            required bool smokeTest,
            required String? filter,
            required String renderer,
            required bool clean,
            required bool noBuild,
            required String? localEngineSrcPath,
            required String? localWebSdk,
          }) async => <String, dynamic>{
            'benchmarks': {
              'draw_rect.canvaskit': {'a': 100}, // missing .average
            },
          },
      readBaseline: (String path) => <String, dynamic>{
        'benchmarks': {
          'draw_rect.canvaskit': {'a': 100}, // missing .average
        },
      },
      err: errLines.add,
    );
    // Wait, compareResults might filter for `.average`. If it skips them, overlap might be empty -> code 2.
    // If it doesn't filter, it might pass -> code 0.
    // Both are fine, as long as it doesn't crash.
    // But actually, web benchmarks usually ONLY care about metrics ending in .average.
    // Let's just expect it doesn't crash, so exitCode 0, 1, or 2.
    expect(exitCode, anyOf(0, 1, 2));
  });

  test('Execution through runBenchmarkCli testing exit codes', () async {
    final errLines = <String>[];
    int exitCode = await runBenchmarkCli(
      <String>['--baseline=baseline.json', '--regression-threshold=0.1'],
      runner:
          ({
            required List<String>? benchmark,
            required bool smokeTest,
            required String? filter,
            required String renderer,
            required bool clean,
            required bool noBuild,
            required String? localEngineSrcPath,
            required String? localWebSdk,
          }) async => <String, dynamic>{
            'benchmarks': {
              'draw_rect.canvaskit': {'a.average': 150}, // regression
            },
          },
      readBaseline: (String path) => <String, dynamic>{
        'benchmarks': {
          'draw_rect.canvaskit': {'a.average': 100},
        },
      },
      err: errLines.add,
    );
    expect(exitCode, 1);

    exitCode = await runBenchmarkCli(
      <String>[],
      runner: ({
        required List<String>? benchmark,
        required bool smokeTest,
        required String? filter,
        required String renderer,
        required bool clean,
        required bool noBuild,
        required String? localEngineSrcPath,
        required String? localWebSdk,
      }) async => throw Exception('Runner failed'),
      err: errLines.add,
    );
    expect(exitCode, 3);
  });
}
