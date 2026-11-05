/// Error raised by domain logic for invalid input or unsatisfiable requests.
///
/// Ported from JS `throw new Error(message)` sites; the message text is kept
/// identical to the web app because it is user-visible.
class DomainError implements Exception {
  const DomainError(this.message);

  final String message;

  @override
  String toString() => message;
}
