// lib/models/property_address.dart

/// Structured property address model for blockchain and database storage
/// Handles both formal address systems (e.g., USA) and informal systems (e.g., many African countries)
class PropertyAddress {
  final String? houseNumber;      // Resident/house number (optional - not available in many countries)
  final String? streetName;       // Street name (optional)
  final String? city;             // City/town/village name
  final String? stateProvince;    // State/Region/Province
  final String? country;          // Country name
  final String? postalCode;       // Zip/postal code (optional)
  final String? additionalInfo;   // Additional landmarks or descriptive information

  // GPS coordinates of the property (from polygon center)
  final double? latitude;
  final double? longitude;

  PropertyAddress({
    this.houseNumber,
    this.streetName,
    this.city,
    this.stateProvince,
    this.country,
    this.postalCode,
    this.additionalInfo,
    this.latitude,
    this.longitude,
  });

  /// Create from JSON (for Firestore and blockchain)
  factory PropertyAddress.fromJson(Map<String, dynamic> json) {
    return PropertyAddress(
      houseNumber: json['houseNumber'] as String?,
      streetName: json['streetName'] as String?,
      city: json['city'] as String?,
      stateProvince: json['stateProvince'] as String?,
      country: json['country'] as String?,
      postalCode: json['postalCode'] as String?,
      additionalInfo: json['additionalInfo'] as String?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
    );
  }

  /// Convert to JSON (for Firestore and blockchain)
  Map<String, dynamic> toJson() {
    return {
      'houseNumber': houseNumber,
      'streetName': streetName,
      'city': city,
      'stateProvince': stateProvince,
      'country': country,
      'postalCode': postalCode,
      'additionalInfo': additionalInfo,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// Format as single-line address string for display
  String toDisplayString() {
    final parts = <String>[];

    // House number and street
    if (houseNumber?.isNotEmpty == true && streetName?.isNotEmpty == true) {
      parts.add('$houseNumber $streetName');
    } else if (streetName?.isNotEmpty == true) {
      parts.add(streetName!);
    }

    // City
    if (city?.isNotEmpty == true) {
      parts.add(city!);
    }

    // State/Province and postal code
    if (stateProvince?.isNotEmpty == true && postalCode?.isNotEmpty == true) {
      parts.add('$stateProvince $postalCode');
    } else if (stateProvince?.isNotEmpty == true) {
      parts.add(stateProvince!);
    } else if (postalCode?.isNotEmpty == true) {
      parts.add(postalCode!);
    }

    // Country
    if (country?.isNotEmpty == true) {
      parts.add(country!);
    }

    // Additional info
    if (additionalInfo?.isNotEmpty == true && parts.isEmpty) {
      // If no formal address, show additional info
      parts.add(additionalInfo!);
    }

    return parts.join(', ');
  }

  /// Format as multi-line address string for detailed display
  String toMultiLineString() {
    final lines = <String>[];

    // House number and street
    if (houseNumber?.isNotEmpty == true && streetName?.isNotEmpty == true) {
      lines.add('$houseNumber $streetName');
    } else if (streetName?.isNotEmpty == true) {
      lines.add(streetName!);
    }

    // City, State/Province, Postal code
    final cityLine = <String>[];
    if (city?.isNotEmpty == true) cityLine.add(city!);
    if (stateProvince?.isNotEmpty == true) cityLine.add(stateProvince!);
    if (postalCode?.isNotEmpty == true) cityLine.add(postalCode!);
    if (cityLine.isNotEmpty) lines.add(cityLine.join(', '));

    // Country
    if (country?.isNotEmpty == true) {
      lines.add(country!);
    }

    // Additional info
    if (additionalInfo?.isNotEmpty == true) {
      lines.add('Note: ${additionalInfo!}');
    }

    return lines.join('\n');
  }

  /// Check if address has any data
  bool get isEmpty =>
      houseNumber == null &&
      streetName == null &&
      city == null &&
      stateProvince == null &&
      country == null &&
      postalCode == null &&
      additionalInfo == null;

  bool get isNotEmpty => !isEmpty;

  /// Copy with method for easy updates
  PropertyAddress copyWith({
    String? houseNumber,
    String? streetName,
    String? city,
    String? stateProvince,
    String? country,
    String? postalCode,
    String? additionalInfo,
    double? latitude,
    double? longitude,
  }) {
    return PropertyAddress(
      houseNumber: houseNumber ?? this.houseNumber,
      streetName: streetName ?? this.streetName,
      city: city ?? this.city,
      stateProvince: stateProvince ?? this.stateProvince,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
