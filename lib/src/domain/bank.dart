/// One gas bank in the inventory. Field names follow the JS bank keys.
class Bank {
  const Bank({
    required this.id,
    required this.name,
    required this.volumeL,
    required this.pressureBar,
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.enabled,
    this.pricePerLitre,
    this.maxPressureBar,
    this.isCompressor,
    this.minimumPressureBar,
    this.gasPresetLink = const UnnamedPresetLink(),
  });

  final String id;
  final String name;
  final double volumeL;
  final double pressureBar;
  final double oxygenPercent;
  final double heliumPercent;
  final bool enabled;

  /// Null when the bank has no price (JS `undefined`/`null`).
  final double? pricePerLitre;

  /// Null when the bank has no pressure ceiling (JS `undefined`/`null`).
  final double? maxPressureBar;

  /// Null when the JS flag is absent; `true` only for compressor banks.
  final bool? isCompressor;

  /// Null when the bank has no minimum source pressure (JS `undefined`/`null`).
  /// The optimizer falls back to its configured or default minimum.
  final double? minimumPressureBar;

  /// Which gas preset the bank is linked to (JS `gasPresetName`). Defaults to
  /// [UnnamedPresetLink], the JS "absent" state.
  final BankGasPresetLink gasPresetLink;

  Bank copyWith({
    String? id,
    String? name,
    double? volumeL,
    double? pressureBar,
    double? oxygenPercent,
    double? heliumPercent,
    bool? enabled,
    double? Function()? pricePerLitre,
    double? Function()? maxPressureBar,
    bool? isCompressor,
    double? Function()? minimumPressureBar,
    BankGasPresetLink? gasPresetLink,
  }) {
    return Bank(
      id: id ?? this.id,
      name: name ?? this.name,
      volumeL: volumeL ?? this.volumeL,
      pressureBar: pressureBar ?? this.pressureBar,
      oxygenPercent: oxygenPercent ?? this.oxygenPercent,
      heliumPercent: heliumPercent ?? this.heliumPercent,
      enabled: enabled ?? this.enabled,
      pricePerLitre: pricePerLitre != null
          ? pricePerLitre()
          : this.pricePerLitre,
      maxPressureBar: maxPressureBar != null
          ? maxPressureBar()
          : this.maxPressureBar,
      isCompressor: isCompressor ?? this.isCompressor,
      minimumPressureBar: minimumPressureBar != null
          ? minimumPressureBar()
          : this.minimumPressureBar,
      gasPresetLink: gasPresetLink ?? this.gasPresetLink,
    );
  }
}

/// The `gasPresetName` state of a [Bank] (JS three states). Typed so that a
/// missing link, a custom mix, and a named preset cannot be confused.
sealed class BankGasPresetLink {
  const BankGasPresetLink();
}

/// JS `gasPresetName: null`: a custom mix. No preset is selected.
final class CustomMixLink extends BankGasPresetLink {
  const CustomMixLink();
}

/// JS `gasPresetName` absent: the link is unknown, so the first preset whose
/// composition matches the bank is selected.
final class UnnamedPresetLink extends BankGasPresetLink {
  const UnnamedPresetLink();
}

/// JS `gasPresetName: '<name>'`: the preset with this name, if it also matches
/// the bank composition.
final class NamedPresetLink extends BankGasPresetLink {
  const NamedPresetLink(this.name);

  final String name;
}
