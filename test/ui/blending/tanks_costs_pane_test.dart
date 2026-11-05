import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/currency_format.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/cost_summary.dart';
import 'package:simplex_blender/src/ui/blending/tanks_costs_pane.dart';

import '../../support/memory_storage.dart';

// Source of truth: tests/cost-summary.test.js (strings and table headers) and
// js/ui/cost-summary.js `NOT_CONFIGURED` / `renderCostSummary` (the tables are
// hidden and the status line shown when `cost` is null or `cost.configured` is false).

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _inputs() => BlendInputs(
  cylinderPreset: _catalinaS80(),
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  targetPressureBar: 195,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: 21,
  targetInWaterTemperatureC: 10,
  waitTargetTemperatureC: 25,
  inletTemperatureC: 21,
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  waitMode: 'minutes',
  waitMinutes: 5,
);

/// Builds an Optimize result with [banks] priced by the controller's own copy.
BlendController _controller(AppController app, List<Bank> banks) =>
    BlendController(
      inputs: _inputs(),
      banks: banks,
      settings: app.settings,
      updateBank: (_) {},
      analytics: const NoopAnalytics(),
    );

Future<void> _pump(
  WidgetTester tester, {
  required BlendController controller,
  required AppController app,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TanksCostsPane(controller: controller, app: app),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('priced default recipe shows gas rows and the gas total', (
    tester,
  ) async {
    final app = AppController(
      storage: MemoryStorage(),
      analytics: const NoopAnalytics(),
    );
    final banks = [
      for (final bank in DEFAULT_BANKS)
        bank.copyWith(pricePerLitre: () => 0.02),
    ];
    final controller = _controller(app, banks);
    await _pump(tester, controller: controller, app: app);

    final cost = controller.blendingCost();
    expect(cost, isNotNull);
    expect(cost!.configured, isTrue);
    expect(cost.gasLines, isNotEmpty);
    expect(find.text('Gas cost'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Total gas cost'), findsOneWidget);
    for (final line in cost.gasLines) {
      expect(find.text(line.name), findsWidgets);
    }
    expect(find.text(cost.gasTotal.toStringAsFixed(2)), findsWidgets);
    expect(find.text(costsNotConfiguredText), findsNothing);
    expect(find.text(costsNoPlanText), findsNothing);
  });

  testWidgets('banner and summary use the currency symbol from settings', (
    tester,
  ) async {
    final app = AppController(
      storage: MemoryStorage(),
      analytics: const NoopAnalytics(),
    );
    final priced = DEFAULT_SETTINGS.copyWith(
      costs: const Costs(
        currencySymbol: 'CHF',
        leftoverDiscountPercent: 0,
        operationPrices: OperationPrices(boost: 1, decant: 1, topUp: 1),
      ),
    );
    expect(app.applySettings(priced), isEmpty);
    final banks = [
      for (final bank in DEFAULT_BANKS)
        bank.copyWith(pricePerLitre: () => 0.02),
    ];
    final controller = _controller(app, banks);
    await _pump(tester, controller: controller, app: app);

    final cost = controller.blendingCost()!;
    expect(find.text('Cost (CHF)'), findsWidgets);
    expect(find.text('Fee (CHF)'), findsOneWidget);
    expect(find.text(formatMoney(cost.total, 'CHF', 2)), findsOneWidget);
  });

  testWidgets('unset costs show the not-configured text and no tables', (
    tester,
  ) async {
    final app = AppController(
      storage: MemoryStorage(),
      analytics: const NoopAnalytics(),
    );
    final banks = [
      for (final bank in DEFAULT_BANKS)
        bank.copyWith(pricePerLitre: () => null),
    ];
    final controller = _controller(app, banks);
    await _pump(tester, controller: controller, app: app);

    expect(controller.blendingCost()!.configured, isFalse);
    expect(find.text(costsNotConfiguredText), findsOneWidget);
    expect(find.text('Total gas cost'), findsNothing);
    expect(find.text('Total cost'), findsNothing);
  });
}
