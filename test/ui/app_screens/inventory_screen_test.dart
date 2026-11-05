import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/blend_defaults.dart';
import 'package:simplex_blender/src/ui/inventory/equipment_summary.dart';
import 'package:simplex_blender/src/ui/inventory/inventory_screen.dart';
import 'package:simplex_blender/src/ui/inventory/supply_banks_section.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../../support/memory_storage.dart';

class _NoopAnalytics implements Analytics {
  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {}
}

Future<void> _pump(WidgetTester tester) async {
  final analytics = _NoopAnalytics();
  final app = AppController(storage: MemoryStorage(), analytics: analytics);
  final blend = BlendController(
    inputs: BlendInputs.fromDefaults(
      defaultBlendInputs(cylinderPresets: app.settings.cylinderPresets),
    ),
    banks: app.banks,
    settings: app.settings,
    updateBank: app.updateBank,
    analytics: analytics,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TourTargetsScope(
          targets: TourTargets(),
          child: InventoryScreen(app: app, blend: blend),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders equipment above supply banks, as in the web markup', (
    tester,
  ) async {
    await _pump(tester);

    final equipmentTop = tester.getTopLeft(find.byType(EquipmentSummary)).dy;
    final banksTop = tester.getTopLeft(find.byType(SupplyBanksSection)).dy;
    expect(equipmentTop, lessThan(banksTop));
  });

  testWidgets('wraps each section in its tour target key', (tester) async {
    await _pump(tester);

    final targets = tester.element(find.byType(InventoryScreen));
    final tourTargets = TourTargetsScope.of(targets);

    final equipmentKeyed = tourTargets
        .keyFor('equipment-section')
        .currentContext;
    final banksKeyed = tourTargets
        .keyFor('supply-banks-section')
        .currentContext;
    expect(equipmentKeyed, isNotNull);
    expect(banksKeyed, isNotNull);
    expect(
      find.descendant(
        of: find.byWidget(equipmentKeyed!.widget),
        matching: find.byType(EquipmentSummary),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byWidget(banksKeyed!.widget),
        matching: find.byType(SupplyBanksSection),
      ),
      findsOneWidget,
    );
  });
}
