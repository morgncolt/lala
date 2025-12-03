import 'package:latlong2/latlong.dart';

/// Represents a major city within a region
class City {
  final String name;
  final LatLng coordinates;
  final String regionId; // Which ADM1 region this city belongs to
  final double zoomLevel;

  const City({
    required this.name,
    required this.coordinates,
    required this.regionId,
    this.zoomLevel = 13.0,
  });
}

/// Database of major cities organized by ADM1 region (state/province level)
class CitiesDatabase {
  static const Map<String, List<City>> citiesByRegion = {
    // ==================== CAMEROON ADM1 REGIONS ====================
    // Centre Region (ADM1)
    'cameroon_centre': [
      City(name: 'Yaoundé', coordinates: LatLng(3.8480, 11.5021), regionId: 'cameroon_centre'),
    ],

    // Littoral Region (ADM1)
    'cameroon_littoral': [
      City(name: 'Douala', coordinates: LatLng(4.0511, 9.7679), regionId: 'cameroon_littoral'),
      City(name: 'Limbe', coordinates: LatLng(4.0227, 9.2055), regionId: 'cameroon_littoral'),
    ],

    // North-West Region (ADM1)
    'cameroon_northwest': [
      City(name: 'Bamenda', coordinates: LatLng(5.9631, 10.1591), regionId: 'cameroon_northwest'),
      City(name: 'Kumbo', coordinates: LatLng(6.2034, 10.6770), regionId: 'cameroon_northwest'),
      City(name: 'Fundong', coordinates: LatLng(6.1942, 10.2773), regionId: 'cameroon_northwest'),
      City(name: 'Bafut', coordinates: LatLng(6.0925, 10.1006), regionId: 'cameroon_northwest'),
    ],

    // South-West Region (ADM1)
    'cameroon_southwest': [
      City(name: 'Buea', coordinates: LatLng(4.1560, 9.2323), regionId: 'cameroon_southwest'),
    ],

    // North Region (ADM1)
    'cameroon_north': [
      City(name: 'Garoua', coordinates: LatLng(9.3012, 13.3964), regionId: 'cameroon_north'),
    ],

    // West Region (ADM1)
    'cameroon_west': [
      City(name: 'Bafoussam', coordinates: LatLng(5.4781, 10.4177), regionId: 'cameroon_west'),
    ],

    // Far North Region (ADM1)
    'cameroon_farnorth': [
      City(name: 'Maroua', coordinates: LatLng(10.5970, 14.3158), regionId: 'cameroon_farnorth'),
    ],

    // Adamawa Region (ADM1)
    'cameroon_adamawa': [
      City(name: 'Ngaoundéré', coordinates: LatLng(7.3167, 13.5833), regionId: 'cameroon_adamawa'),
    ],

    // East Region (ADM1)
    'cameroon_east': [
      City(name: 'Bertoua', coordinates: LatLng(4.5772, 13.6844), regionId: 'cameroon_east'),
    ],

    // Fallback: All Cameroon cities (ADM0 level for backwards compatibility)
    'cameroon': [
      City(name: 'Yaoundé', coordinates: LatLng(3.8480, 11.5021), regionId: 'cameroon'),
      City(name: 'Douala', coordinates: LatLng(4.0511, 9.7679), regionId: 'cameroon'),
      City(name: 'Bamenda', coordinates: LatLng(5.9631, 10.1591), regionId: 'cameroon'),
      City(name: 'Kumbo', coordinates: LatLng(6.2034, 10.6770), regionId: 'cameroon'),
      City(name: 'Fundong', coordinates: LatLng(6.1942, 10.2773), regionId: 'cameroon'),
      City(name: 'Bafut', coordinates: LatLng(6.0925, 10.1006), regionId: 'cameroon'),
      City(name: 'Garoua', coordinates: LatLng(9.3012, 13.3964), regionId: 'cameroon'),
      City(name: 'Bafoussam', coordinates: LatLng(5.4781, 10.4177), regionId: 'cameroon'),
      City(name: 'Maroua', coordinates: LatLng(10.5970, 14.3158), regionId: 'cameroon'),
      City(name: 'Ngaoundéré', coordinates: LatLng(7.3167, 13.5833), regionId: 'cameroon'),
      City(name: 'Bertoua', coordinates: LatLng(4.5772, 13.6844), regionId: 'cameroon'),
      City(name: 'Limbe', coordinates: LatLng(4.0227, 9.2055), regionId: 'cameroon'),
      City(name: 'Buea', coordinates: LatLng(4.1560, 9.2323), regionId: 'cameroon'),
    ],

    // ==================== UNITED STATES ADM1 STATES ====================
    // California (ADM1)
    'california': [
      City(name: 'Los Angeles', coordinates: LatLng(34.0522, -118.2437), regionId: 'california'),
      City(name: 'San Francisco', coordinates: LatLng(37.7749, -122.4194), regionId: 'california'),
      City(name: 'San Diego', coordinates: LatLng(32.7157, -117.1611), regionId: 'california'),
    ],

    // New York (ADM1)
    'new_york': [
      City(name: 'New York City', coordinates: LatLng(40.7128, -74.0060), regionId: 'new_york'),
    ],

    // Texas (ADM1)
    'texas': [
      City(name: 'Houston', coordinates: LatLng(29.7604, -95.3698), regionId: 'texas'),
      City(name: 'Dallas', coordinates: LatLng(32.7767, -96.7970), regionId: 'texas'),
      City(name: 'Austin', coordinates: LatLng(30.2672, -97.7431), regionId: 'texas'),
    ],

    // Florida (ADM1)
    'florida': [
      City(name: 'Miami', coordinates: LatLng(25.7617, -80.1918), regionId: 'florida'),
      City(name: 'Orlando', coordinates: LatLng(28.5383, -81.3792), regionId: 'florida'),
    ],

    // Illinois (ADM1)
    'illinois': [
      City(name: 'Chicago', coordinates: LatLng(41.8781, -87.6298), regionId: 'illinois'),
    ],

    // Washington (ADM1)
    'washington': [
      City(name: 'Seattle', coordinates: LatLng(47.6062, -122.3321), regionId: 'washington'),
    ],

    // Georgia (ADM1)
    'georgia': [
      City(name: 'Atlanta', coordinates: LatLng(33.7490, -84.3880), regionId: 'georgia'),
    ],

    // Massachusetts (ADM1)
    'massachusetts': [
      City(name: 'Boston', coordinates: LatLng(42.3601, -71.0589), regionId: 'massachusetts'),
    ],

    // Colorado (ADM1)
    'colorado': [
      City(name: 'Denver', coordinates: LatLng(39.7392, -104.9903), regionId: 'colorado'),
    ],

    // Fallback: All US cities (ADM0 level for backwards compatibility)
    'united_states': [
      City(name: 'Los Angeles, CA', coordinates: LatLng(34.0522, -118.2437), regionId: 'united_states'),
      City(name: 'San Francisco, CA', coordinates: LatLng(37.7749, -122.4194), regionId: 'united_states'),
      City(name: 'San Diego, CA', coordinates: LatLng(32.7157, -117.1611), regionId: 'united_states'),
      City(name: 'New York City, NY', coordinates: LatLng(40.7128, -74.0060), regionId: 'united_states'),
      City(name: 'Houston, TX', coordinates: LatLng(29.7604, -95.3698), regionId: 'united_states'),
      City(name: 'Dallas, TX', coordinates: LatLng(32.7767, -96.7970), regionId: 'united_states'),
      City(name: 'Austin, TX', coordinates: LatLng(30.2672, -97.7431), regionId: 'united_states'),
      City(name: 'Miami, FL', coordinates: LatLng(25.7617, -80.1918), regionId: 'united_states'),
      City(name: 'Orlando, FL', coordinates: LatLng(28.5383, -81.3792), regionId: 'united_states'),
      City(name: 'Chicago, IL', coordinates: LatLng(41.8781, -87.6298), regionId: 'united_states'),
      City(name: 'Seattle, WA', coordinates: LatLng(47.6062, -122.3321), regionId: 'united_states'),
      City(name: 'Atlanta, GA', coordinates: LatLng(33.7490, -84.3880), regionId: 'united_states'),
      City(name: 'Boston, MA', coordinates: LatLng(42.3601, -71.0589), regionId: 'united_states'),
      City(name: 'Denver, CO', coordinates: LatLng(39.7392, -104.9903), regionId: 'united_states'),
    ],

    // ==================== NIGERIA ADM1 STATES ====================
    // Lagos State (ADM1)
    'nigeria_lagos': [
      City(name: 'Lagos', coordinates: LatLng(6.5244, 3.3792), regionId: 'nigeria_lagos'),
    ],

    // FCT Abuja (ADM1)
    'nigeria_fct': [
      City(name: 'Abuja', coordinates: LatLng(9.0765, 7.3986), regionId: 'nigeria_fct'),
    ],

    // Kano State (ADM1)
    'nigeria_kano': [
      City(name: 'Kano', coordinates: LatLng(12.0022, 8.5920), regionId: 'nigeria_kano'),
    ],

    // Oyo State (ADM1)
    'nigeria_oyo': [
      City(name: 'Ibadan', coordinates: LatLng(7.3775, 3.9470), regionId: 'nigeria_oyo'),
    ],

    // Rivers State (ADM1)
    'nigeria_rivers': [
      City(name: 'Port Harcourt', coordinates: LatLng(4.8156, 7.0498), regionId: 'nigeria_rivers'),
    ],

    // Edo State (ADM1)
    'nigeria_edo': [
      City(name: 'Benin City', coordinates: LatLng(6.3350, 5.6037), regionId: 'nigeria_edo'),
    ],

    // Kaduna State (ADM1)
    'nigeria_kaduna': [
      City(name: 'Kaduna', coordinates: LatLng(10.5105, 7.4165), regionId: 'nigeria_kaduna'),
    ],

    // Enugu State (ADM1)
    'nigeria_enugu': [
      City(name: 'Enugu', coordinates: LatLng(6.4403, 7.4966), regionId: 'nigeria_enugu'),
    ],

    // Plateau State (ADM1)
    'nigeria_plateau': [
      City(name: 'Jos', coordinates: LatLng(9.8965, 8.8583), regionId: 'nigeria_plateau'),
    ],

    // Cross River State (ADM1)
    'nigeria_crossriver': [
      City(name: 'Calabar', coordinates: LatLng(4.9517, 8.3417), regionId: 'nigeria_crossriver'),
    ],

    // Akwa Ibom State (ADM1)
    'nigeria_akwaibom': [
      City(name: 'Uyo', coordinates: LatLng(5.0378, 7.9085), regionId: 'nigeria_akwaibom'),
    ],

    // Delta State (ADM1)
    'nigeria_delta': [
      City(name: 'Warri', coordinates: LatLng(5.5160, 5.7500), regionId: 'nigeria_delta'),
    ],

    // Imo State (ADM1)
    'nigeria_imo': [
      City(name: 'Owerri', coordinates: LatLng(5.4840, 7.0351), regionId: 'nigeria_imo'),
    ],

    // Borno State (ADM1)
    'nigeria_borno': [
      City(name: 'Maiduguri', coordinates: LatLng(11.8311, 13.1510), regionId: 'nigeria_borno'),
    ],

    // Ogun State (ADM1)
    'nigeria_ogun': [
      City(name: 'Abeokuta', coordinates: LatLng(7.1475, 3.3619), regionId: 'nigeria_ogun'),
    ],

    // Fallback: All Nigeria cities (ADM0 level for backwards compatibility)
    'nigeria': [
      City(name: 'Lagos', coordinates: LatLng(6.5244, 3.3792), regionId: 'nigeria'),
      City(name: 'Abuja', coordinates: LatLng(9.0765, 7.3986), regionId: 'nigeria'),
      City(name: 'Kano', coordinates: LatLng(12.0022, 8.5920), regionId: 'nigeria'),
      City(name: 'Ibadan', coordinates: LatLng(7.3775, 3.9470), regionId: 'nigeria'),
      City(name: 'Port Harcourt', coordinates: LatLng(4.8156, 7.0498), regionId: 'nigeria'),
      City(name: 'Benin City', coordinates: LatLng(6.3350, 5.6037), regionId: 'nigeria'),
      City(name: 'Kaduna', coordinates: LatLng(10.5105, 7.4165), regionId: 'nigeria'),
      City(name: 'Enugu', coordinates: LatLng(6.4403, 7.4966), regionId: 'nigeria'),
      City(name: 'Jos', coordinates: LatLng(9.8965, 8.8583), regionId: 'nigeria'),
      City(name: 'Calabar', coordinates: LatLng(4.9517, 8.3417), regionId: 'nigeria'),
      City(name: 'Uyo', coordinates: LatLng(5.0378, 7.9085), regionId: 'nigeria'),
      City(name: 'Warri', coordinates: LatLng(5.5160, 5.7500), regionId: 'nigeria'),
      City(name: 'Owerri', coordinates: LatLng(5.4840, 7.0351), regionId: 'nigeria'),
      City(name: 'Maiduguri', coordinates: LatLng(11.8311, 13.1510), regionId: 'nigeria'),
      City(name: 'Abeokuta', coordinates: LatLng(7.1475, 3.3619), regionId: 'nigeria'),
    ],

    // ==================== KENYA ADM1 COUNTIES ====================
    // Nairobi County (ADM1)
    'kenya_nairobi': [
      City(name: 'Nairobi', coordinates: LatLng(-1.2864, 36.8172), regionId: 'kenya_nairobi'),
    ],

    // Mombasa County (ADM1)
    'kenya_mombasa': [
      City(name: 'Mombasa', coordinates: LatLng(-4.0435, 39.6682), regionId: 'kenya_mombasa'),
    ],

    // Kisumu County (ADM1)
    'kenya_kisumu': [
      City(name: 'Kisumu', coordinates: LatLng(-0.0917, 34.7680), regionId: 'kenya_kisumu'),
    ],

    // Nakuru County (ADM1)
    'kenya_nakuru': [
      City(name: 'Nakuru', coordinates: LatLng(-0.3031, 36.0800), regionId: 'kenya_nakuru'),
    ],

    // Uasin Gishu County (ADM1)
    'kenya_uasingishu': [
      City(name: 'Eldoret', coordinates: LatLng(0.5143, 35.2698), regionId: 'kenya_uasingishu'),
    ],

    // Kiambu County (ADM1)
    'kenya_kiambu': [
      City(name: 'Thika', coordinates: LatLng(-1.0332, 37.0693), regionId: 'kenya_kiambu'),
    ],

    // Kilifi County (ADM1)
    'kenya_kilifi': [
      City(name: 'Malindi', coordinates: LatLng(-3.2167, 40.1167), regionId: 'kenya_kilifi'),
    ],

    // Trans-Nzoia County (ADM1)
    'kenya_transnzoia': [
      City(name: 'Kitale', coordinates: LatLng(1.0167, 35.0000), regionId: 'kenya_transnzoia'),
    ],

    // Garissa County (ADM1)
    'kenya_garissa': [
      City(name: 'Garissa', coordinates: LatLng(-0.4536, 39.6401), regionId: 'kenya_garissa'),
    ],

    // Kakamega County (ADM1)
    'kenya_kakamega': [
      City(name: 'Kakamega', coordinates: LatLng(0.2827, 34.7519), regionId: 'kenya_kakamega'),
    ],

    // Fallback: All Kenya cities (ADM0 level for backwards compatibility)
    'kenya': [
      City(name: 'Nairobi', coordinates: LatLng(-1.2864, 36.8172), regionId: 'kenya'),
      City(name: 'Mombasa', coordinates: LatLng(-4.0435, 39.6682), regionId: 'kenya'),
      City(name: 'Kisumu', coordinates: LatLng(-0.0917, 34.7680), regionId: 'kenya'),
      City(name: 'Nakuru', coordinates: LatLng(-0.3031, 36.0800), regionId: 'kenya'),
      City(name: 'Eldoret', coordinates: LatLng(0.5143, 35.2698), regionId: 'kenya'),
      City(name: 'Thika', coordinates: LatLng(-1.0332, 37.0693), regionId: 'kenya'),
      City(name: 'Malindi', coordinates: LatLng(-3.2167, 40.1167), regionId: 'kenya'),
      City(name: 'Kitale', coordinates: LatLng(1.0167, 35.0000), regionId: 'kenya'),
      City(name: 'Garissa', coordinates: LatLng(-0.4536, 39.6401), regionId: 'kenya'),
      City(name: 'Kakamega', coordinates: LatLng(0.2827, 34.7519), regionId: 'kenya'),
    ],

    // ==================== GHANA ADM1 REGIONS ====================
    // Greater Accra Region (ADM1)
    'ghana_greateraccra': [
      City(name: 'Accra', coordinates: LatLng(5.6037, -0.1870), regionId: 'ghana_greateraccra'),
      City(name: 'Tema', coordinates: LatLng(5.6698, -0.0166), regionId: 'ghana_greateraccra'),
    ],

    // Ashanti Region (ADM1)
    'ghana_ashanti': [
      City(name: 'Kumasi', coordinates: LatLng(6.6885, -1.6244), regionId: 'ghana_ashanti'),
    ],

    // Northern Region (ADM1)
    'ghana_northern': [
      City(name: 'Tamale', coordinates: LatLng(9.4034, -0.8424), regionId: 'ghana_northern'),
    ],

    // Western Region (ADM1)
    'ghana_western': [
      City(name: 'Takoradi', coordinates: LatLng(4.8845, -1.7554), regionId: 'ghana_western'),
    ],

    // Central Region (ADM1)
    'ghana_central': [
      City(name: 'Cape Coast', coordinates: LatLng(5.1053, -1.2466), regionId: 'ghana_central'),
    ],

    // Bono Region (ADM1)
    'ghana_bono': [
      City(name: 'Sunyani', coordinates: LatLng(7.3397, -2.3269), regionId: 'ghana_bono'),
    ],

    // Volta Region (ADM1)
    'ghana_volta': [
      City(name: 'Ho', coordinates: LatLng(6.6008, 0.4719), regionId: 'ghana_volta'),
    ],

    // Eastern Region (ADM1)
    'ghana_eastern': [
      City(name: 'Koforidua', coordinates: LatLng(6.0940, -0.2600), regionId: 'ghana_eastern'),
    ],

    // Fallback: All Ghana cities (ADM0 level for backwards compatibility)
    'ghana': [
      City(name: 'Accra', coordinates: LatLng(5.6037, -0.1870), regionId: 'ghana'),
      City(name: 'Kumasi', coordinates: LatLng(6.6885, -1.6244), regionId: 'ghana'),
      City(name: 'Tamale', coordinates: LatLng(9.4034, -0.8424), regionId: 'ghana'),
      City(name: 'Takoradi', coordinates: LatLng(4.8845, -1.7554), regionId: 'ghana'),
      City(name: 'Cape Coast', coordinates: LatLng(5.1053, -1.2466), regionId: 'ghana'),
      City(name: 'Tema', coordinates: LatLng(5.6698, -0.0166), regionId: 'ghana'),
      City(name: 'Sunyani', coordinates: LatLng(7.3397, -2.3269), regionId: 'ghana'),
      City(name: 'Ho', coordinates: LatLng(6.6008, 0.4719), regionId: 'ghana'),
      City(name: 'Koforidua', coordinates: LatLng(6.0940, -0.2600), regionId: 'ghana'),
    ],
  };

  /// Get cities for a specific region
  static List<City> getCitiesForRegion(String regionId) {
    // Normalize region ID - handle different formats:
    // "North-West#0" -> "cameroon_northwest"
    // "cameroon_northwest" -> "cameroon_northwest"
    // "cameroon" -> "cameroon"

    var normalizedId = regionId.trim().toLowerCase();

    // Remove #0, #1, etc. suffixes
    normalizedId = normalizedId.replaceAll(RegExp(r'#\d+'), '');

    // Replace spaces with underscores
    normalizedId = normalizedId.replaceAll(RegExp(r'\s+'), '_');

    // Handle region name mappings for all countries
    final regionMappings = {
      // Cameroon regions
      'north-west': 'cameroon_northwest',
      'north_west': 'cameroon_northwest',
      'south-west': 'cameroon_southwest',
      'south_west': 'cameroon_southwest',
      'centre': 'cameroon_centre',
      'littoral': 'cameroon_littoral',
      'north': 'cameroon_north',
      'west': 'cameroon_west',
      'far_north': 'cameroon_farnorth',
      'adamawa': 'cameroon_adamawa',
      'east': 'cameroon_east',

      // Nigeria states
      'lagos': 'nigeria_lagos',
      'lagos_state': 'nigeria_lagos',
      'fct': 'nigeria_fct',
      'abuja': 'nigeria_fct',
      'kano': 'nigeria_kano',
      'kano_state': 'nigeria_kano',
      'oyo': 'nigeria_oyo',
      'oyo_state': 'nigeria_oyo',
      'rivers': 'nigeria_rivers',
      'rivers_state': 'nigeria_rivers',
      'edo': 'nigeria_edo',
      'edo_state': 'nigeria_edo',
      'kaduna': 'nigeria_kaduna',
      'kaduna_state': 'nigeria_kaduna',
      'enugu': 'nigeria_enugu',
      'enugu_state': 'nigeria_enugu',
      'plateau': 'nigeria_plateau',
      'plateau_state': 'nigeria_plateau',
      'cross_river': 'nigeria_crossriver',
      'crossriver': 'nigeria_crossriver',
      'akwa_ibom': 'nigeria_akwaibom',
      'akwaibom': 'nigeria_akwaibom',
      'delta': 'nigeria_delta',
      'delta_state': 'nigeria_delta',
      'imo': 'nigeria_imo',
      'imo_state': 'nigeria_imo',
      'borno': 'nigeria_borno',
      'borno_state': 'nigeria_borno',
      'ogun': 'nigeria_ogun',
      'ogun_state': 'nigeria_ogun',

      // Kenya counties
      'nairobi': 'kenya_nairobi',
      'nairobi_county': 'kenya_nairobi',
      'mombasa': 'kenya_mombasa',
      'mombasa_county': 'kenya_mombasa',
      'kisumu': 'kenya_kisumu',
      'kisumu_county': 'kenya_kisumu',
      'nakuru': 'kenya_nakuru',
      'nakuru_county': 'kenya_nakuru',
      'uasin_gishu': 'kenya_uasingishu',
      'uasingishu': 'kenya_uasingishu',
      'kiambu': 'kenya_kiambu',
      'kiambu_county': 'kenya_kiambu',
      'kilifi': 'kenya_kilifi',
      'kilifi_county': 'kenya_kilifi',
      'trans-nzoia': 'kenya_transnzoia',
      'trans_nzoia': 'kenya_transnzoia',
      'transnzoia': 'kenya_transnzoia',
      'garissa': 'kenya_garissa',
      'garissa_county': 'kenya_garissa',
      'kakamega': 'kenya_kakamega',
      'kakamega_county': 'kenya_kakamega',

      // Ghana regions
      'greater_accra': 'ghana_greateraccra',
      'greateraccra': 'ghana_greateraccra',
      'ashanti': 'ghana_ashanti',
      'northern': 'ghana_northern',
      'western': 'ghana_western',
      'central': 'ghana_central',
      'bono': 'ghana_bono',
      'volta': 'ghana_volta',
      'eastern': 'ghana_eastern',
    };

    // Check if we need to map the region
    if (regionMappings.containsKey(normalizedId)) {
      normalizedId = regionMappings[normalizedId]!;
    }

    return citiesByRegion[normalizedId] ?? [];
  }

  /// Get all cities across all regions
  static List<City> getAllCities() {
    final results = <City>[];
    for (final cities in citiesByRegion.values) {
      results.addAll(cities);
    }
    return results;
  }

  /// Search for cities by name across all regions
  static List<City> searchCities(String query) {
    final results = <City>[];
    final lowerQuery = query.toLowerCase();

    for (final cities in citiesByRegion.values) {
      results.addAll(
        cities.where((city) => city.name.toLowerCase().contains(lowerQuery)),
      );
    }

    return results;
  }

  /// Get friendly region name for display
  static String getRegionDisplayName(String regionId) {
    final names = {
      // ADM0 (Countries)
      'cameroon': 'Cameroon',
      'nigeria': 'Nigeria',
      'kenya': 'Kenya',
      'ghana': 'Ghana',
      'united_states': 'United States',

      // Cameroon ADM1 (Regions)
      'cameroon_centre': 'Centre Region',
      'cameroon_littoral': 'Littoral Region',
      'cameroon_northwest': 'North-West Region',
      'cameroon_southwest': 'South-West Region',
      'cameroon_north': 'North Region',
      'cameroon_west': 'West Region',
      'cameroon_farnorth': 'Far North Region',
      'cameroon_adamawa': 'Adamawa Region',
      'cameroon_east': 'East Region',

      // Nigeria ADM1 (States)
      'nigeria_lagos': 'Lagos State',
      'nigeria_fct': 'FCT Abuja',
      'nigeria_kano': 'Kano State',
      'nigeria_oyo': 'Oyo State',
      'nigeria_rivers': 'Rivers State',
      'nigeria_edo': 'Edo State',
      'nigeria_kaduna': 'Kaduna State',
      'nigeria_enugu': 'Enugu State',
      'nigeria_plateau': 'Plateau State',
      'nigeria_crossriver': 'Cross River State',
      'nigeria_akwaibom': 'Akwa Ibom State',
      'nigeria_delta': 'Delta State',
      'nigeria_imo': 'Imo State',
      'nigeria_borno': 'Borno State',
      'nigeria_ogun': 'Ogun State',

      // Kenya ADM1 (Counties)
      'kenya_nairobi': 'Nairobi County',
      'kenya_mombasa': 'Mombasa County',
      'kenya_kisumu': 'Kisumu County',
      'kenya_nakuru': 'Nakuru County',
      'kenya_uasingishu': 'Uasin Gishu County',
      'kenya_kiambu': 'Kiambu County',
      'kenya_kilifi': 'Kilifi County',
      'kenya_transnzoia': 'Trans-Nzoia County',
      'kenya_garissa': 'Garissa County',
      'kenya_kakamega': 'Kakamega County',

      // Ghana ADM1 (Regions)
      'ghana_greateraccra': 'Greater Accra Region',
      'ghana_ashanti': 'Ashanti Region',
      'ghana_northern': 'Northern Region',
      'ghana_western': 'Western Region',
      'ghana_central': 'Central Region',
      'ghana_bono': 'Bono Region',
      'ghana_volta': 'Volta Region',
      'ghana_eastern': 'Eastern Region',

      // US ADM1 (States)
      'california': 'California',
      'new_york': 'New York',
      'texas': 'Texas',
      'florida': 'Florida',
      'illinois': 'Illinois',
      'washington': 'Washington',
      'georgia': 'Georgia',
      'massachusetts': 'Massachusetts',
      'colorado': 'Colorado',
    };
    return names[regionId] ?? regionId;
  }

  /// Get ADM1 regions for a given ADM0 country
  static Map<String, String> getAdm1RegionsForCountry(String countryId) {
    final adm1Regions = <String, String>{};

    // Find all region IDs that start with the country prefix
    for (final regionId in citiesByRegion.keys) {
      if (regionId.startsWith('${countryId}_')) {
        adm1Regions[regionId] = getRegionDisplayName(regionId);
      }
    }

    return adm1Regions;
  }

  /// Check if a region ID is an ADM0 (country-level) region
  static bool isAdm0Region(String regionId) {
    final normalizedId = regionId.trim().toLowerCase();

    // ADM0 countries (no #0 suffix, no sub-region names)
    final adm0Countries = ['cameroon', 'nigeria', 'kenya', 'ghana', 'united_states'];

    // If it has a #0, #1 suffix, it's an ADM1 region
    if (normalizedId.contains(RegExp(r'#\d+'))) {
      return false;
    }

    // If it's a known ADM1 region name, it's not ADM0
    final knownAdm1Regions = [
      // Cameroon regions
      'north-west', 'north_west', 'south-west', 'south_west',
      'centre', 'littoral', 'north', 'west', 'far_north', 'adamawa', 'east',

      // Nigeria states
      'lagos', 'lagos_state', 'fct', 'abuja', 'kano', 'kano_state',
      'oyo', 'oyo_state', 'rivers', 'rivers_state', 'edo', 'edo_state',
      'kaduna', 'kaduna_state', 'enugu', 'enugu_state', 'plateau', 'plateau_state',
      'cross_river', 'crossriver', 'akwa_ibom', 'akwaibom',
      'delta', 'delta_state', 'imo', 'imo_state', 'borno', 'borno_state',
      'ogun', 'ogun_state',

      // Kenya counties
      'nairobi', 'nairobi_county', 'mombasa', 'mombasa_county',
      'kisumu', 'kisumu_county', 'nakuru', 'nakuru_county',
      'uasin_gishu', 'uasingishu', 'kiambu', 'kiambu_county',
      'kilifi', 'kilifi_county', 'trans-nzoia', 'trans_nzoia', 'transnzoia',
      'garissa', 'garissa_county', 'kakamega', 'kakamega_county',

      // Ghana regions
      'greater_accra', 'greateraccra', 'ashanti', 'northern',
      'western', 'central', 'bono', 'volta', 'eastern',

      // US states
      'california', 'texas', 'florida', 'new_york', 'illinois',
      'washington', 'georgia', 'massachusetts', 'colorado'
    ];

    if (knownAdm1Regions.contains(normalizedId.replaceAll(RegExp(r'\s+'), '_').replaceAll('-', '_'))) {
      return false;
    }

    // Check if it's a known ADM0 country
    return adm0Countries.contains(normalizedId);
  }
}

/// Represents an ADM1 region with its cities
class RegionWithCities {
  final String regionId;
  final String regionName;
  final List<City> cities;
  final int cityCount;

  const RegionWithCities({
    required this.regionId,
    required this.regionName,
    required this.cities,
    required this.cityCount,
  });
}
