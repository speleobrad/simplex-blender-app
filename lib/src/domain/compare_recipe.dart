import 'dart:math' as math;

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';
import 'package:simplex_blender/src/domain/gas_input.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

part 'compare_recipe/inputs.dart';
part 'compare_recipe/validation_results.dart';
part 'compare_recipe/protocol_results.dart';
part 'compare_recipe/internal_state.dart';
part 'compare_recipe/public_helpers.dart';
part 'compare_recipe/private_helpers.dart';
part 'compare_recipe/validation.dart';
part 'compare_recipe/physics_solver.dart';
part 'compare_recipe/step_builders.dart';
part 'compare_recipe/protocol_builder.dart';

// JS NaN/null stand-in: `double.nan` where JS used a non-finite number or
// null. Every comparison against NaN is false, matching the JS guards.

// ignore: constant_identifier_names
const String COMPRESSOR_AIR_ID = 'compressor-air';
// ignore: constant_identifier_names
const double COMPRESSOR_AIR_DEFAULT_PRESSURE_BAR = 232;
// ignore: constant_identifier_names
const double MAX_PRESSURE_BAR = 350;
// ignore: constant_identifier_names
const double MAX_WAIT_MINUTES = 1440;
// ignore: constant_identifier_names
const double MIN_WAIT_TEMPERATURE_C = -100;
// ignore: constant_identifier_names
const double MAX_WAIT_TEMPERATURE_C = 100;
// ignore: constant_identifier_names
const double PRESSURE_TOLERANCE_BAR = 1e-7;
// ignore: constant_identifier_names
const List<String> STEP_COLORS = [
  '#06b6d4',
  '#f59e0b',
  '#10b981',
  '#a855f7',
  '#ec4899',
];

const Set<String> _knownRowTypes = {'drain', 'keep', 'add', 'wait'};

class CompareOption {
  const CompareOption({required this.value, required this.label});

  final String value;
  final String label;
}

// ignore: constant_identifier_names
const List<CompareOption> COMPARE_ROW_TYPES = [
  CompareOption(value: 'drain', label: 'Drain'),
  CompareOption(value: 'add', label: 'Add gas'),
  CompareOption(value: 'wait', label: 'Wait'),
];

// ignore: constant_identifier_names
const List<CompareOption> COMPARE_METHODS = [
  CompareOption(value: 'decant', label: 'Decant'),
  CompareOption(value: 'boost', label: 'Boost'),
  CompareOption(value: 'compressor', label: 'Compressor'),
];
