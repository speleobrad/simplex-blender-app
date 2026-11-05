import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/ui/inventory/equipment_summary.dart';
import 'package:simplex_blender/src/ui/inventory/supply_banks_section.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

/// Inventory screen (JS `screen-inventory`, `index.html` 779-840). Equipment
/// comes first and supply banks second, matching the web markup.
///
/// The tour highlights the two sections through [TourTargetsScope] ids
/// `equipment-section` and `supply-banks-section`.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.app, required this.blend});

  final AppController app;
  final BlendController blend;

  @override
  Widget build(BuildContext context) {
    final targets = TourTargetsScope.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: targets.keyFor('equipment-section'),
            child: EquipmentSummary(app: app),
          ),
          const SizedBox(height: 24),
          KeyedSubtree(
            key: targets.keyFor('supply-banks-section'),
            child: SupplyBanksSection(app: app, blend: blend),
          ),
        ],
      ),
    );
  }
}
