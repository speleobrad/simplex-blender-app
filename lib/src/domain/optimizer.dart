/// Port of the safety section of `js/optimizer.js` (JS lines 25–633).
///
/// The cylinder record stays a `Map<String, Object?>` with the JS key names
/// (read through the typed helpers in `optimizer/values.dart`); a missing JS
/// key is an absent map key. Physics, thermal, settings, and protocol/thermal
/// step records are typed (`PhysicsInput`, `ThermalInput`, `BlendSettings`,
/// `ProtocolStep`, `ThermalStep`). Public entries take only the JS-shaped blend
/// input map and parse it with `_parseBlendInput`.
library;

import 'dart:math' as math;

import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/simplex.dart';
import 'package:simplex_blender/src/domain/gas_input.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/leftover_attractiveness.dart';
import 'package:simplex_blender/src/domain/salvage.dart';

part 'optimizer/blend_input.dart';

part 'optimizer/safety.dart';
part 'optimizer/values.dart';
part 'optimizer/schedule.dart';
part 'optimizer/linear_program.dart';
part 'optimizer/blend_plan.dart';
part 'optimizer/blend_safety.dart';
part 'optimizer/blend_metrics.dart';
part 'optimizer/blend_no_salvage_search.dart';
part 'optimizer/blend_no_salvage.dart';
part 'optimizer/salvage_cascade.dart';
part 'optimizer/salvage_search.dart';
part 'optimizer/thermal_blend.dart';
part 'optimizer/blend_entry.dart';
