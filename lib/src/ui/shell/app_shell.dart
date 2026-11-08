import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';
import 'package:simplex_blender/src/domain/theme.dart';
import 'package:simplex_blender/src/ui/about/about_screen.dart';
import 'package:simplex_blender/src/ui/blending/blending_screen.dart';
import 'package:simplex_blender/src/ui/inventory/inventory_screen.dart';
import 'package:simplex_blender/src/ui/onboarding/onboarding_tour.dart';
import 'package:simplex_blender/src/ui/settings/settings_screen.dart';
import 'package:simplex_blender/src/ui/shell/app_theme.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_screen.dart';

/// Window width at and above which the primary navigation is a side rail.
const double _railBreakpoint = 840;

const String _themeNotSavedMessage =
    'Theme changed for this session only; preference could not be saved.';

/// Primary destinations in display order. Index matches the [IndexedStack]
/// child order in [_SimplexBlenderAppState._buildBody].
class _Destination {
  const _Destination(this.screen, this.label, this.icon);

  final String screen;
  final String label;
  final IconData icon;
}

const List<_Destination> _destinations = <_Destination>[
  _Destination('blending', 'Blending', Icons.science_outlined),
  _Destination('what-if', 'What-if', Icons.tune),
  _Destination('inventory', 'Inventory', Icons.inventory_2_outlined),
  _Destination('settings', 'Settings', Icons.settings_outlined),
  _Destination('about', 'About', Icons.info_outline),
];

/// Root widget: the Material app, primary navigation, theme, guided tour, and
/// the wiring between the app, Blending, and What-if controllers.
class SimplexBlenderApp extends StatefulWidget {
  const SimplexBlenderApp({
    super.key,
    required this.app,
    required this.blend,
    required this.whatIf,
  });

  final AppController app;
  final BlendController blend;
  final WhatIfController whatIf;

  @override
  State<SimplexBlenderApp> createState() => _SimplexBlenderAppState();
}

class _SimplexBlenderAppState extends State<SimplexBlenderApp> {
  final TourTargets _targets = TourTargets();
  late String _lastScreen;
  late bool _tourOpen;
  int _tourGeneration = 0;
  String _themeStatus = '';

  AppController get _app => widget.app;

  @override
  void initState() {
    super.initState();
    _lastScreen = _app.primaryScreen;
    _tourOpen = !_app.onboarding.wizardSeen;
    widget.whatIf.updateSharedInputs(
      banks: _app.banks,
      settings: _app.settings,
    );
    widget.blend.updateSharedInputs(banks: _app.banks, settings: _app.settings);
    _app.addListener(_onAppChanged);
    widget.blend.addListener(_onBlendChanged);
  }

  @override
  void dispose() {
    _app.removeListener(_onAppChanged);
    widget.blend.removeListener(_onBlendChanged);
    super.dispose();
  }

  /// Pushes shared inputs to both controllers and enters What-if on the
  /// transition into it (JS `setActiveScreen` → `initializeWhatIfScenario`
  /// and `runWhatIf`). Covers navigation from the tour as well as the rail.
  void _onAppChanged() {
    widget.blend.updateSharedInputs(banks: _app.banks, settings: _app.settings);
    widget.whatIf.updateSharedInputs(
      banks: _app.banks,
      settings: _app.settings,
    );
    final screen = _app.primaryScreen;
    if (screen != _lastScreen) {
      _lastScreen = screen;
      if (screen == 'what-if') {
        _enterWhatIf();
      }
    }
    setState(() {});
  }

  void _onBlendChanged() {
    widget.whatIf.setInletTemperatureC(widget.blend.inputs.inletTemperatureC);
  }

  /// JS `initializeWhatIfScenario` followed by `runWhatIf`. The scenario
  /// snapshot is taken once; later entries only re-run it.
  void _enterWhatIf() {
    final inputs = widget.blend.inputs;
    widget.whatIf.initializeScenario(
      initialPressureBar: inputs.initialPressureBar,
      initialOxygenPercent: inputs.initialOxygenPercent,
      initialHeliumPercent: inputs.initialHeliumPercent,
      cylinderPresetName: inputs.cylinderPreset.name,
      ambientTemperatureC: inputs.ambientTemperatureC,
      coolingMedium: inputs.coolingMedium,
      waterSubmersionPercent: inputs.waterSubmersionPercent,
      targetInWaterTemperatureC: inputs.targetInWaterTemperatureC,
    );
    widget.whatIf.runWhatIf();
  }

  void _selectDestination(int index) {
    final screen = _destinations[index].screen;
    if (screen == _app.primaryScreen) {
      // JS re-runs What-if when its tab is clicked again.
      if (screen == 'what-if') {
        _enterWhatIf();
      }
      return;
    }
    _app.setPrimaryScreen(screen);
  }

  void _toggleTheme() {
    final next = _app.themePreference == 'dark' ? 'light' : 'dark';
    final saved = _app.setThemePreference(next);
    setState(() {
      _themeStatus = saved ? '' : _themeNotSavedMessage;
    });
  }

  void _openTour() {
    final step = WIZARD_STEPS.first;
    _app.navigate(screen: step.screen, settingsCategory: step.settingsCategory);
    setState(() {
      _tourGeneration += 1;
      _tourOpen = true;
    });
  }

  void _closeTour() {
    setState(() {
      _tourOpen = false;
    });
  }

  void _onFactoryReset() {
    widget.whatIf.resetForFactoryReset();
    widget.blend.resetForFactoryReset();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeOrDefault(_app.themePreference) == 'dark';
    return TourTargetsScope(
      targets: _targets,
      child: MaterialApp(
        title: 'Simplex blender',
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        // Builder so MediaQuery and Theme resolve below MaterialApp.
        home: Builder(builder: _buildHome),
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    final index = _destinations.indexWhere(
      (destination) => destination.screen == _app.primaryScreen,
    );
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final body = _buildBody(index, wide);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simplex blender'),
        actions: _headerActions(context),
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildRail(index),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide ? null : _buildNavigationBar(index),
    );
  }

  List<Widget> _headerActions(BuildContext context) {
    final isDark = themeOrDefault(_app.themePreference) == 'dark';
    return <Widget>[
      Tooltip(
        message: isDark ? 'Switch to light theme' : 'Switch to dark theme',
        child: TextButton.icon(
          onPressed: _toggleTheme,
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
          label: Text(isDark ? 'Light' : 'Dark'),
        ),
      ),
      IconButton(
        tooltip: 'Show the guided tour',
        icon: const Icon(Icons.auto_fix_high),
        onPressed: _openTour,
      ),
    ];
  }

  Widget _buildNavigationBar(int index) {
    return KeyedSubtree(
      key: _targets.keyFor('primary-navigation'),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _selectDestination,
        destinations: <NavigationDestination>[
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }

  Widget _buildRail(int index) {
    return KeyedSubtree(
      key: _targets.keyFor('primary-navigation'),
      child: NavigationRail(
        selectedIndex: index,
        onDestinationSelected: _selectDestination,
        labelType: NavigationRailLabelType.all,
        destinations: <NavigationRailDestination>[
          for (final destination in _destinations)
            NavigationRailDestination(
              icon: Icon(destination.icon),
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(int index, bool wide) {
    final warnings = _app.storageWarning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_themeStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(_themeStatus, style: const TextStyle(fontSize: 12)),
          ),
        if (warnings.isNotEmpty) _StorageWarningBox(messages: warnings),
        if (_app.cylinderMigrationNotice case final notice?)
          _CylinderMigrationNotice(
            message: notice,
            onDismiss: _app.dismissCylinderMigrationNotice,
          ),
        Expanded(
          child: Stack(
            children: <Widget>[
              IndexedStack(
                index: index,
                children: <Widget>[
                  BlendingScreen(controller: widget.blend, app: _app),
                  WhatIfScreen(
                    controller: widget.whatIf,
                    blend: widget.blend,
                    app: _app,
                  ),
                  InventoryScreen(app: _app, blend: widget.blend),
                  SettingsScreen(app: _app, onFactoryReset: _onFactoryReset),
                  AboutScreen(app: _app),
                ],
              ),
              if (_tourOpen)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: wide ? 16 : 80,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: OnboardingTour(
                        key: ValueKey<int>(_tourGeneration),
                        app: _app,
                        onClosed: _closeTour,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Port of the JS `#storage-warning` banner: an alert shown above the screens
/// while any storage warning applies.
class _StorageWarningBox extends StatelessWidget {
  const _StorageWarningBox({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          border: Border.all(color: scheme.tertiary),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          messages.join(' '),
          style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
        ),
      ),
    );
  }
}

/// One-time informational notice that saved cylinder presets were given
/// dimensions from the nearest standard cylinder.
class _CylinderMigrationNotice extends StatelessWidget {
  const _CylinderMigrationNotice({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          border: Border.all(color: scheme.secondary),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('cylinder-migration-dismiss'),
              onPressed: onDismiss,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}
