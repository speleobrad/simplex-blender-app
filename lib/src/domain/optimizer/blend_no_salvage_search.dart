part of '../optimizer.dart';

/// Shared closure state of JS `solveBlendWithoutSalvage` (`solveAtPressure`,
/// `safetyFor`, `isUnsafe`, `safeAtPressure`). Field names follow the JS
/// closure variables.
class _BlendSearch {
  _BlendSearch({
    required this.initialMoles,
    required this.initialOxygenPercent,
    required this.initialHeliumPercent,
    required this.targetPressureBar,
    required this.targetMoles,
    required this.targetOxygenPercent,
    required this.targetHeliumPercent,
    required this.volumeL,
    required this.temperatureC,
    required this.useVdw,
    required this.maxCompressorPressureBar,
    required this.maxBoosterOutputPressureBar,
    required this.activeBanks,
    required this.bankMaxMoles,
    required this.bankDensityByBankId,
  });

  final double initialMoles;
  final double initialOxygenPercent;
  final double initialHeliumPercent;
  final double targetPressureBar;
  final double targetMoles;
  final double targetOxygenPercent;
  final double targetHeliumPercent;
  final double volumeL;
  final double temperatureC;
  final bool useVdw;
  final double maxCompressorPressureBar;
  final double maxBoosterOutputPressureBar;
  final List<Bank> activeBanks;
  final List<double> bankMaxMoles;
  final Map<String, double> bankDensityByBankId;

  /// JS `targetMolesAtPressure` (shared by solveAtPressure and safeAtPressure).
  double _targetMolesAt(double pressureBar) {
    return pressureBar == targetPressureBar
        ? targetMoles
        : calcMolarDensity(
                pressureBar,
                targetOxygenPercent,
                targetHeliumPercent,
                temperatureC,
                useVdw,
              ) *
              volumeL;
  }

  /// JS `solveAtPressure`. [candidateBankMaxMoles] null means the closure
  /// [bankMaxMoles] (JS default parameter).
  _LinearProgramResult solveAtPressure(
    double pressureBar, {
    bool prioritizeTransferSafety = false,
    String? preferredBankId,
    String? excludedBankId,
    List<double>? candidateBankMaxMoles,
  }) {
    return _solveTargetBlendAtMoles(
      initialMoles: initialMoles,
      targetMoles: _targetMolesAt(pressureBar),
      initialOxygenPercent: initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent,
      targetOxygenPercent: targetOxygenPercent,
      targetHeliumPercent: targetHeliumPercent,
      activeBanks: activeBanks,
      bankMaxMoles: candidateBankMaxMoles ?? bankMaxMoles,
      prioritizeTransferSafety: prioritizeTransferSafety,
      preferredBankId: preferredBankId,
      excludedBankId: excludedBankId,
    );
  }

  /// JS `safetyFor`: transfer safety first; equipment safety only when the
  /// transfer check has no error. [pressureBar] null means targetPressureBar.
  ({double margin, String? error}) safetyFor(
    _LinearProgramResult result, {
    double? pressureBar,
  }) {
    final checkedPressureBar = pressureBar ?? targetPressureBar;
    final transferResult = _transferSafety(
      solverResult: result,
      activeBanks: activeBanks,
      bankDensityByBankId: bankDensityByBankId,
      initialOxygenPercent: initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent,
      volumeL: volumeL,
      temperatureC: temperatureC,
      useVdw: useVdw,
      targetPressureBar: checkedPressureBar,
      maxCompressorPressureBar: maxCompressorPressureBar,
    );
    if (transferResult.error != null) {
      return transferResult;
    }
    return _equipmentSafety(
      solverResult: result,
      activeBanks: activeBanks,
      bankDensityByBankId: bankDensityByBankId,
      initialOxygenPercent: initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent,
      volumeL: volumeL,
      temperatureC: temperatureC,
      useVdw: useVdw,
      targetPressureBar: checkedPressureBar,
      maxCompressorPressureBar: maxCompressorPressureBar,
      maxBoosterOutputPressureBar: maxBoosterOutputPressureBar,
    );
  }

  /// JS `isUnsafe`: the safety error message, or null when safe.
  String? isUnsafe(_LinearProgramResult result, {double? pressureBar}) {
    return safetyFor(result, pressureBar: pressureBar).error;
  }

  /// JS `safeAtPressure`: a feasible, safe recipe at [pressureBar], or null.
  _LinearProgramResult? safeAtPressure(
    double pressureBar, {
    _LinearProgramResult? seedResult,
  }) {
    final oxygenRichBanks = <Bank>[
      for (var index = 0; index < activeBanks.length; index++)
        if (activeBanks[index].oxygenPercent > 25 && bankMaxMoles[index] > 1e-9)
          activeBanks[index],
    ];
    _LinearProgramResult? feasibleSeedResult =
        seedResult != null && seedResult.feasible ? seedResult : null;
    var candidate = solveAtPressure(
      pressureBar,
      prioritizeTransferSafety: true,
    );
    if (candidate.feasible) {
      feasibleSeedResult ??= candidate;
      if (isUnsafe(candidate, pressureBar: pressureBar) == null) {
        return candidate;
      }
    }

    for (final bank in oxygenRichBanks) {
      candidate = solveAtPressure(
        pressureBar,
        prioritizeTransferSafety: true,
        preferredBankId: bank.id,
      );
      if (candidate.feasible) {
        feasibleSeedResult ??= candidate;
        if (isUnsafe(candidate, pressureBar: pressureBar) == null) {
          return candidate;
        }
      }
    }

    for (final bank in oxygenRichBanks) {
      candidate = solveAtPressure(
        pressureBar,
        prioritizeTransferSafety: true,
        excludedBankId: bank.id,
      );
      if (candidate.feasible) {
        feasibleSeedResult ??= candidate;
        if (isUnsafe(candidate, pressureBar: pressureBar) == null) {
          return candidate;
        }
      }
    }

    if (oxygenRichBanks.length < 2) {
      return null;
    }

    final targetMolesAtPressure = _targetMolesAt(pressureBar);
    final targetOxygenMoles =
        targetMolesAtPressure * (targetOxygenPercent / 100);
    final oxygenMolesPerBank = targetOxygenMoles / oxygenRichBanks.length;
    final splitCaps = <double>[
      for (var index = 0; index < activeBanks.length; index++)
        activeBanks[index].oxygenPercent > 25
            ? _jsMathMin(
                bankMaxMoles[index],
                oxygenMolesPerBank / (activeBanks[index].oxygenPercent / 100),
              )
            : bankMaxMoles[index],
    ];
    candidate = solveAtPressure(
      pressureBar,
      prioritizeTransferSafety: true,
      candidateBankMaxMoles: splitCaps,
    );
    if (candidate.feasible) {
      feasibleSeedResult ??= candidate;
      if (isUnsafe(candidate, pressureBar: pressureBar) == null) {
        return candidate;
      }
    }

    const oxygenShares = <double>[0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8, 0.1, 0.9];

    ({_LinearProgramResult result, double margin}) tryPairShare(
      Bank firstBank,
      int firstBankIndex,
      Bank secondBank,
      int secondBankIndex,
      double firstShare,
    ) {
      final pairCaps = List<double>.of(bankMaxMoles);
      pairCaps[firstBankIndex] = _jsMathMin(
        pairCaps[firstBankIndex],
        (targetOxygenMoles * firstShare) / (firstBank.oxygenPercent / 100),
      );
      pairCaps[secondBankIndex] = _jsMathMin(
        pairCaps[secondBankIndex],
        (targetOxygenMoles * (1 - firstShare)) /
            (secondBank.oxygenPercent / 100),
      );
      final result = solveAtPressure(
        pressureBar,
        prioritizeTransferSafety: true,
        candidateBankMaxMoles: pairCaps,
      );
      return (
        result: result,
        margin: result.feasible
            ? safetyFor(result, pressureBar: pressureBar).margin
            : double.negativeInfinity,
      );
    }

    for (
      var firstIndex = 0;
      firstIndex < oxygenRichBanks.length;
      firstIndex++
    ) {
      final firstBank = oxygenRichBanks[firstIndex];
      final firstBankIndex = activeBanks.indexOf(firstBank);
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < oxygenRichBanks.length;
        secondIndex++
      ) {
        final secondBank = oxygenRichBanks[secondIndex];
        final secondBankIndex = activeBanks.indexOf(secondBank);
        final outsideOxygenMoles = _maximumOutsideOxygenMoles(
          initialMoles: initialMoles,
          initialOxygenPercent: initialOxygenPercent,
          initialHeliumPercent: initialHeliumPercent,
          targetMoles: targetMolesAtPressure,
          targetOxygenPercent: targetOxygenPercent,
          targetHeliumPercent: targetHeliumPercent,
          activeBanks: activeBanks,
          bankMaxMoles: bankMaxMoles,
          excludedBankIds: <String>{firstBank.id, secondBank.id},
        );
        final requiredPairOxygenMoles = _jsMathMax(
          0.0,
          targetOxygenMoles - outsideOxygenMoles,
        );
        final feasibleShareRanges = _feasibleOxygenShareRanges(
          targetOxygenMoles,
          requiredPairOxygenMoles,
          bankMaxMoles[firstBankIndex] * (firstBank.oxygenPercent / 100),
          bankMaxMoles[secondBankIndex] * (secondBank.oxygenPercent / 100),
        );

        for (final shareRange in feasibleShareRanges) {
          final minimumShare = shareRange[0];
          final maximumShare = shareRange[1];
          double? feasibleShareSeed;
          if (feasibleSeedResult != null && targetOxygenMoles > 1e-9) {
            final firstVariable =
                feasibleSeedResult.variableNames[firstBankIndex + 1];
            final secondVariable =
                feasibleSeedResult.variableNames[secondBankIndex + 1];
            final firstOxygenMoles =
                _jsOrZero(feasibleSeedResult.solution?[firstVariable]) *
                (firstBank.oxygenPercent / 100);
            final secondOxygenMoles =
                _jsOrZero(feasibleSeedResult.solution?[secondVariable]) *
                (secondBank.oxygenPercent / 100);
            final lowerSeed = firstOxygenMoles / targetOxygenMoles;
            final upperSeed = 1 - secondOxygenMoles / targetOxygenMoles;
            final seedShare = _jsMathMax(
              minimumShare,
              _jsMathMin(maximumShare, (lowerSeed + upperSeed) / 2),
            );
            final seedAttempt = tryPairShare(
              firstBank,
              firstBankIndex,
              secondBank,
              secondBankIndex,
              seedShare,
            );
            if (seedAttempt.result.feasible) {
              feasibleShareSeed = seedShare;
              if (seedAttempt.margin >= -1e-9) {
                return seedAttempt.result;
              }
            }
          }

          final shareSamples = <double>{
            ...oxygenShares.where(
              (share) => share >= minimumShare && share <= maximumShare,
            ),
            minimumShare,
            (minimumShare + maximumShare) / 2,
            maximumShare,
          };
          for (final firstShare in shareSamples) {
            final attempt = tryPairShare(
              firstBank,
              firstBankIndex,
              secondBank,
              secondBankIndex,
              firstShare,
            );
            if (attempt.result.feasible) {
              feasibleShareSeed ??= firstShare;
              if (attempt.margin >= -1e-9) {
                return attempt.result;
              }
            }
          }
          if (feasibleShareSeed == null) {
            continue;
          }

          var feasibleMinimum = feasibleShareSeed;
          final minimumAttempt = tryPairShare(
            firstBank,
            firstBankIndex,
            secondBank,
            secondBankIndex,
            minimumShare,
          );
          if (minimumAttempt.result.feasible) {
            feasibleMinimum = minimumShare;
            if (minimumAttempt.margin >= -1e-9) {
              return minimumAttempt.result;
            }
          } else {
            var infeasibleShare = minimumShare;
            var feasibleShare = feasibleShareSeed;
            for (var iteration = 0; iteration < 32; iteration++) {
              final share = (infeasibleShare + feasibleShare) / 2;
              final attempt = tryPairShare(
                firstBank,
                firstBankIndex,
                secondBank,
                secondBankIndex,
                share,
              );
              if (attempt.result.feasible) {
                feasibleShare = share;
                if (attempt.margin >= -1e-9) {
                  return attempt.result;
                }
              } else {
                infeasibleShare = share;
              }
            }
            feasibleMinimum = feasibleShare;
          }

          var feasibleMaximum = feasibleShareSeed;
          final maximumAttempt = tryPairShare(
            firstBank,
            firstBankIndex,
            secondBank,
            secondBankIndex,
            maximumShare,
          );
          if (maximumAttempt.result.feasible) {
            feasibleMaximum = maximumShare;
            if (maximumAttempt.margin >= -1e-9) {
              return maximumAttempt.result;
            }
          } else {
            var feasibleShare = feasibleShareSeed;
            var infeasibleShare = maximumShare;
            for (var iteration = 0; iteration < 32; iteration++) {
              final share = (feasibleShare + infeasibleShare) / 2;
              final attempt = tryPairShare(
                firstBank,
                firstBankIndex,
                secondBank,
                secondBankIndex,
                share,
              );
              if (attempt.result.feasible) {
                feasibleShare = share;
                if (attempt.margin >= -1e-9) {
                  return attempt.result;
                }
              } else {
                infeasibleShare = share;
              }
            }
            feasibleMaximum = feasibleShare;
          }

          final samePriority =
              _boostPriority(firstBank) == _boostPriority(secondBank);
          final orderBoundary = samePriority
              ? firstBank.oxygenPercent /
                    (firstBank.oxygenPercent + secondBank.oxygenPercent)
              : null;
          final intervals =
              orderBoundary != null &&
                  orderBoundary > feasibleMinimum &&
                  orderBoundary < feasibleMaximum
              ? <List<double>>[
                  <double>[feasibleMinimum, orderBoundary],
                  <double>[orderBoundary, feasibleMaximum],
                ]
              : <List<double>>[
                  <double>[feasibleMinimum, feasibleMaximum],
                ];
          for (final interval in intervals) {
            var left = interval[0];
            var right = interval[1];
            for (var iteration = 0; iteration < 32; iteration++) {
              final leftProbe = left + (right - left) / 3;
              final rightProbe = right - (right - left) / 3;
              final leftResult = tryPairShare(
                firstBank,
                firstBankIndex,
                secondBank,
                secondBankIndex,
                leftProbe,
              );
              if (leftResult.result.feasible && leftResult.margin >= -1e-9) {
                return leftResult.result;
              }
              final rightResult = tryPairShare(
                firstBank,
                firstBankIndex,
                secondBank,
                secondBankIndex,
                rightProbe,
              );
              if (rightResult.result.feasible && rightResult.margin >= -1e-9) {
                return rightResult.result;
              }
              if (leftResult.margin > rightResult.margin) {
                right = rightProbe;
              } else {
                left = leftProbe;
              }
            }
            final refined = tryPairShare(
              firstBank,
              firstBankIndex,
              secondBank,
              secondBankIndex,
              (left + right) / 2,
            );
            if (refined.result.feasible && refined.margin >= -1e-9) {
              return refined.result;
            }
          }
        }
      }
    }

    return null;
  }
}
