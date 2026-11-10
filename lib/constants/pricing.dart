import '../utils/validators.dart';

/// Fixed rate card (customer-facing estimates and the driver's default
/// price when completing a delivery). Kept in one place so the order
/// screen, order history and driver screens can't drift apart.
const double purifiedPricePerGallon = 20.0;
const double mineralPricePerGallon = 20.0;

/// Returns the price per gallon for a given water type with fallback error handling.
double pricePerGallonFor(String? waterType) {
  if (waterType == null || waterType.trim().isEmpty) {
    return purifiedPricePerGallon;
  }
  final cleanType = waterType.trim().toLowerCase();
  if (cleanType == 'mineral') {
    return mineralPricePerGallon;
  } else if (cleanType == 'purified') {
    return purifiedPricePerGallon;
  }
  return purifiedPricePerGallon;
}

/// Error handler and validator for gallon quantity input strings.
/// Ensures input is numbers-only, positive, and non-empty.
/// Returns an error prompt message if invalid, or null if valid.
String? validateGallonInput(String? input) {
  final numberError = InputValidators.numbersOnly(input, fieldName: 'Gallon quantity');
  if (numberError != null) return numberError;

  final gallons = int.tryParse(input!.trim());
  if (gallons == null || gallons <= 0) {
    return 'Gallons quantity must be greater than 0. Please try again.';
  }
  if (gallons > 1000) {
    return 'Gallons quantity cannot exceed 1,000. Please try again.';
  }
  return null;
}

/// Computes the order total price safely with error handling for invalid inputs.
/// Returns a tuple with total amount and optional error prompt message.
({double total, String? error}) computeOrderTotal({
  required String? gallonInput,
  required String? waterType,
}) {
  final errorMsg = validateGallonInput(gallonInput);
  if (errorMsg != null) {
    return (total: 0.0, error: errorMsg);
  }

  final gallons = int.parse(gallonInput!.trim());
  final rate = pricePerGallonFor(waterType);
  return (total: gallons * rate, error: null);
}
