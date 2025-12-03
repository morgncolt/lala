// lib/widgets/address_input_widget.dart

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import '../models/property_address.dart';

/// Widget for structured address input with GPS auto-fill capability
///
/// This widget provides separate text fields for each address component
/// and can automatically populate city, state, and country from GPS coordinates
class AddressInputWidget extends StatefulWidget {
  final PropertyAddress? initialAddress;
  final double? latitude;
  final double? longitude;
  final Function(PropertyAddress) onAddressChanged;

  const AddressInputWidget({
    super.key,
    this.initialAddress,
    this.latitude,
    this.longitude,
    required this.onAddressChanged,
  });

  @override
  State<AddressInputWidget> createState() => _AddressInputWidgetState();
}

class _AddressInputWidgetState extends State<AddressInputWidget> {
  // Text controllers for each field
  late TextEditingController houseNumberController;
  late TextEditingController streetNameController;
  late TextEditingController cityController;
  late TextEditingController stateProvinceController;
  late TextEditingController countryController;
  late TextEditingController postalCodeController;
  late TextEditingController additionalInfoController;

  bool _isAutoFilling = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data or empty
    houseNumberController = TextEditingController(text: widget.initialAddress?.houseNumber ?? '');
    streetNameController = TextEditingController(text: widget.initialAddress?.streetName ?? '');
    cityController = TextEditingController(text: widget.initialAddress?.city ?? '');
    stateProvinceController = TextEditingController(text: widget.initialAddress?.stateProvince ?? '');
    countryController = TextEditingController(text: widget.initialAddress?.country ?? '');
    postalCodeController = TextEditingController(text: widget.initialAddress?.postalCode ?? '');
    additionalInfoController = TextEditingController(text: widget.initialAddress?.additionalInfo ?? '');

    // Add listeners to notify parent when any field changes
    houseNumberController.addListener(_notifyChange);
    streetNameController.addListener(_notifyChange);
    cityController.addListener(_notifyChange);
    stateProvinceController.addListener(_notifyChange);
    countryController.addListener(_notifyChange);
    postalCodeController.addListener(_notifyChange);
    additionalInfoController.addListener(_notifyChange);
  }

  @override
  void dispose() {
    houseNumberController.dispose();
    streetNameController.dispose();
    cityController.dispose();
    stateProvinceController.dispose();
    countryController.dispose();
    postalCodeController.dispose();
    additionalInfoController.dispose();
    super.dispose();
  }

  /// Notify parent widget when address changes
  void _notifyChange() {
    widget.onAddressChanged(PropertyAddress(
      houseNumber: houseNumberController.text.trim().isEmpty ? null : houseNumberController.text.trim(),
      streetName: streetNameController.text.trim().isEmpty ? null : streetNameController.text.trim(),
      city: cityController.text.trim().isEmpty ? null : cityController.text.trim(),
      stateProvince: stateProvinceController.text.trim().isEmpty ? null : stateProvinceController.text.trim(),
      country: countryController.text.trim().isEmpty ? null : countryController.text.trim(),
      postalCode: postalCodeController.text.trim().isEmpty ? null : postalCodeController.text.trim(),
      additionalInfo: additionalInfoController.text.trim().isEmpty ? null : additionalInfoController.text.trim(),
      latitude: widget.latitude,
      longitude: widget.longitude,
    ));
  }

  /// Auto-fill city, state, and country from GPS coordinates using reverse geocoding
  Future<void> _autoFillFromGPS() async {
    if (widget.latitude == null || widget.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No GPS coordinates available')),
      );
      return;
    }

    setState(() => _isAutoFilling = true);

    try {
      // Reverse geocode the coordinates
      final placemarks = await placemarkFromCoordinates(
        widget.latitude!,
        widget.longitude!,
      );

      if (placemarks.isEmpty) {
        throw Exception('No address found for these coordinates');
      }

      final place = placemarks.first;

      // Auto-fill only if fields are empty (don't overwrite user input)
      if (cityController.text.isEmpty && place.locality?.isNotEmpty == true) {
        cityController.text = place.locality!;
      }

      if (stateProvinceController.text.isEmpty && place.administrativeArea?.isNotEmpty == true) {
        stateProvinceController.text = place.administrativeArea!;
      }

      if (countryController.text.isEmpty && place.country?.isNotEmpty == true) {
        countryController.text = place.country!;
      }

      if (postalCodeController.text.isEmpty && place.postalCode?.isNotEmpty == true) {
        postalCodeController.text = place.postalCode!;
      }

      // Also try to extract street info if available
      if (streetNameController.text.isEmpty && place.street?.isNotEmpty == true) {
        streetNameController.text = place.street!;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address auto-filled from GPS location'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Auto-fill error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to auto-fill address: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAutoFilling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with auto-fill button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Property Address',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.latitude != null && widget.longitude != null)
              TextButton.icon(
                onPressed: _isAutoFilling ? null : _autoFillFromGPS,
                icon: _isAutoFilling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.location_searching, size: 18),
                label: Text(_isAutoFilling ? 'Loading...' : 'Auto-fill'),
              ),
          ],
        ),
        const SizedBox(height: 8),

        Text(
          'All fields are optional. Enter what is available in your region.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),

        // House/Resident number
        TextField(
          controller: houseNumberController,
          decoration: const InputDecoration(
            labelText: 'House/Resident Number',
            hintText: 'e.g., 123',
            border: OutlineInputBorder(),
            helperText: 'Optional - not all regions use this',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),

        // Street name
        TextField(
          controller: streetNameController,
          decoration: const InputDecoration(
            labelText: 'Street Name',
            hintText: 'e.g., Main Street',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),

        // City (auto-fillable)
        TextField(
          controller: cityController,
          decoration: InputDecoration(
            labelText: 'City/Town/Village',
            hintText: 'e.g., Lagos',
            border: const OutlineInputBorder(),
            suffixIcon: widget.latitude != null
                ? const Icon(Icons.auto_fix_high, size: 18, color: Colors.blue)
                : null,
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),

        // State/Province (auto-fillable)
        TextField(
          controller: stateProvinceController,
          decoration: InputDecoration(
            labelText: 'State/Region/Province',
            hintText: 'e.g., Lagos State',
            border: const OutlineInputBorder(),
            suffixIcon: widget.latitude != null
                ? const Icon(Icons.auto_fix_high, size: 18, color: Colors.blue)
                : null,
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),

        // Country (auto-fillable)
        TextField(
          controller: countryController,
          decoration: InputDecoration(
            labelText: 'Country',
            hintText: 'e.g., Nigeria',
            border: const OutlineInputBorder(),
            suffixIcon: widget.latitude != null
                ? const Icon(Icons.auto_fix_high, size: 18, color: Colors.blue)
                : null,
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),

        // Postal/Zip code (auto-fillable)
        TextField(
          controller: postalCodeController,
          decoration: InputDecoration(
            labelText: 'Postal/Zip Code',
            hintText: 'e.g., 100001',
            border: const OutlineInputBorder(),
            helperText: 'Optional - not all regions use this',
            suffixIcon: widget.latitude != null
                ? const Icon(Icons.auto_fix_high, size: 18, color: Colors.blue)
                : null,
          ),
        ),
        const SizedBox(height: 12),

        // Additional info (for landmarks, informal directions)
        TextField(
          controller: additionalInfoController,
          decoration: const InputDecoration(
            labelText: 'Additional Info / Landmarks',
            hintText: 'e.g., Near central market, behind the mosque',
            border: OutlineInputBorder(),
            helperText: 'Useful for areas without formal addresses',
          ),
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}
