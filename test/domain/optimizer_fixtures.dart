/// Shared optimizer test input: a JS-shaped map that mirrors `defaultInput` in
/// `tests/optimizer.test.js`. Each call returns a fresh map, so a test can edit
/// its copy without affecting other tests.
Map<String, Object?> defaultOptimizerInput() {
  return <String, Object?>{
    'cylinder': <String, Object?>{
      'volumeL': 12.0,
      'initialPressureBar': 80.0,
      'initialOxygenPercent': 21.0,
      'initialHeliumPercent': 35.0,
      'targetPressureBar': 210.0,
      'targetOxygenPercent': 18.0,
      'targetHeliumPercent': 45.0,
    },
    'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
    'banks': <Object?>[
      <String, Object?>{
        'id': 'bank-he',
        'name': 'Pure Helium',
        'volumeL': 50.0,
        'pressureBar': 200.0,
        'maxPressureBar': 350.0,
        'minimumPressureBar': 15.0,
        'oxygenPercent': 0.0,
        'heliumPercent': 100.0,
        'enabled': true,
      },
      <String, Object?>{
        'id': 'bank-1845',
        'name': 'Tx 18/45 Bank',
        'volumeL': 50.0,
        'pressureBar': 200.0,
        'maxPressureBar': 350.0,
        'minimumPressureBar': 20.0,
        'oxygenPercent': 18.0,
        'heliumPercent': 45.0,
        'enabled': true,
      },
      <String, Object?>{
        'id': 'bank-o2',
        'name': 'Pure Oxygen',
        'volumeL': 40.0,
        'pressureBar': 180.0,
        'maxPressureBar': 350.0,
        'minimumPressureBar': 10.0,
        'oxygenPercent': 100.0,
        'heliumPercent': 0.0,
        'enabled': true,
      },
    ],
    'settings': <String, Object?>{
      'booster': <String, Object?>{
        'maxCompressorPressureBar': 350.0,
        'maxBoosterOutputPressureBar': 350.0,
      },
    },
  };
}

/// Deep copy of a JS-shaped input map (nested maps and lists are copied; scalars
/// are shared, since they are immutable).
Map<String, Object?> cloneOptimizerInput(Map<String, Object?> input) {
  return _copyJsValue(input)! as Map<String, Object?>;
}

Object? _copyJsValue(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key: _copyJsValue(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _copyJsValue(item)];
  }
  return value;
}
