import 'package:flutter/services.dart';

/// Keyboard for decimal, signed numeric text fields.
const TextInputType signedDecimalKeyboard = TextInputType.numberWithOptions(
  decimal: true,
  signed: true,
);
