import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'auth_service.dart';

class ActiveLocation {
  final int? addressId;
  final String formattedAddress;
  final String city;
  final String state;
  final String postalCode;
  final double latitude;
  final double longitude;
  final String source;
  final String? placeId;

  const ActiveLocation({
    required this.addressId,
    required this.formattedAddress,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.latitude,
    required this.longitude,
    required this.source,
    this.placeId,
  });

  factory ActiveLocation.fromJson(Map<String, dynamic> json) => ActiveLocation(
    addressId: json['address_id'] as int?,
    formattedAddress: json['formatted_address'] as String? ?? '',
    city: json['city'] as String? ?? '',
    state: json['state'] as String? ?? '',
    postalCode: json['postal_code'] as String? ?? '',
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    source: json['source'] as String? ?? 'manual',
    placeId: json['place_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'address_id': addressId,
    'formatted_address': formattedAddress,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'latitude': latitude,
    'longitude': longitude,
    'source': source,
    'place_id': placeId,
  };
}

class SavedAddress {
  final int id;
  final String label;
  final String houseNumber;
  final String street;
  final String area;
  final String city;
  final String state;
  final String postalCode;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  final bool isDefault;

  const SavedAddress({
    required this.id,
    required this.label,
    required this.houseNumber,
    required this.street,
    required this.area,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    required this.placeId,
    required this.isDefault,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
    id: json['id'] as int,
    label: json['label'] as String,
    houseNumber: json['house_number'] as String? ?? '',
    street: json['street'] as String? ?? '',
    area: json['area'] as String? ?? '',
    city: json['city'] as String? ?? '',
    state: json['state'] as String? ?? '',
    postalCode: json['postal_code'] as String? ?? '',
    formattedAddress: json['formatted_address'] as String,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    placeId: json['place_id'] as String?,
    isDefault: json['is_default'] as bool? ?? false,
  );

  Map<String, dynamic> toPayload() => {
    'label': label,
    'house_number': houseNumber,
    'street': street,
    'area': area,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'formatted_address': formattedAddress,
    if (latitude != null && longitude != null) 'latitude': latitude,
    if (latitude != null && longitude != null) 'longitude': longitude,
    'place_id': placeId,
    'is_default': isDefault,
  };
}

class PlaceSuggestion {
  final String placeId;
  final String description;
  const PlaceSuggestion(this.placeId, this.description);

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      PlaceSuggestion(
        json['place_id'] as String,
        json['description'] as String,
      );
}

class NearbyProvider {
  final int id;
  final String name;
  final String category;
  final String description;
  final double latitude;
  final double longitude;
  final String address;
  final String? imageUrl;
  final double? rating;
  final int? reviewCount;
  final String? price;
  final bool isVerified;
  final bool isAvailable;
  final String? phone;
  final bool? openNow;
  final String? source;
  final double distanceKm;

  const NearbyProvider({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.imageUrl,
    required this.rating,
    required this.reviewCount,
    required this.price,
    required this.isVerified,
    required this.isAvailable,
    required this.phone,
    required this.openNow,
    required this.source,
    required this.distanceKm,
  });

  factory NearbyProvider.fromJson(Map<String, dynamic> json) => NearbyProvider(
    id: json['id'] as int,
    name: json['name'] as String,
    category: json['category'] as String,
    description: json['description'] as String? ?? '',
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    address: json['address'] as String,
    imageUrl: json['image_url'] as String?,
    rating: (json['rating'] as num?)?.toDouble(),
    reviewCount: json['review_count'] as int?,
    price: json['price'] as String?,
    isVerified: json['is_verified'] as bool? ?? false,
    isAvailable: json['is_available'] as bool? ?? false,
    phone: json['phone'] as String?,
    openNow: json['open_now'] as bool?,
    source: json['source'] as String?,
    distanceKm: (json['distance_km'] as num).toDouble(),
  );
}

class LocationService extends ChangeNotifier {
  final AuthService auth;
  ActiveLocation? selected;
  List<SavedAddress> addresses = const [];
  bool loading = false;
  String? loadError;

  LocationService(this.auth);

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final addressResponse = await auth.getAuthenticated('/api/addresses');
      addresses = (addressResponse['addresses'] as List)
          .map(
            (value) =>
                SavedAddress.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList();
      final locationResponse = await auth.getAuthenticated('/api/location');
      final location = locationResponse['location'];
      selected = location == null
          ? null
          : ActiveLocation.fromJson(Map<String, dynamic>.from(location as Map));
    } on AuthApiException catch (error) {
      loadError = error.message;
    } catch (_) {
      loadError = 'Could not load saved locations.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectAddress(SavedAddress address) async {
    final result = await auth.putAuthenticated('/api/location', {
      'address_id': address.id,
    });
    selected = ActiveLocation.fromJson(
      Map<String, dynamic>.from(result['location'] as Map),
    );
    notifyListeners();
  }

  Future<void> selectLocation(ActiveLocation location) async {
    final result = await auth.putAuthenticated(
      '/api/location',
      location.toJson(),
    );
    selected = ActiveLocation.fromJson(
      Map<String, dynamic>.from(result['location'] as Map),
    );
    notifyListeners();
  }

  Future<void> useCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AuthApiException(
        'Location services are off. Enable location in macOS System Settings and try again.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const AuthApiException(
        'Location permission was denied. In Chrome, allow Location for this site or choose a saved/manual location.',
      );
    }
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 18),
        ),
      );
    } on TimeoutException {
      throw const AuthApiException(
        'Location request timed out. Try again or search for an address.',
      );
    } on LocationServiceDisabledException {
      throw const AuthApiException(
        'Location services are off. Enable location in macOS System Settings.',
      );
    } on PermissionDeniedException {
      throw const AuthApiException(
        'Chrome denied location access. Allow Location for this site or choose an address manually.',
      );
    } catch (_) {
      throw const AuthApiException(
        'Chrome could not determine your location. Try again or choose an address manually.',
      );
    }

    ActiveLocation location;
    try {
      final result = await auth.getAuthenticated(
        '/api/location/reverse-geocode?latitude=${position.latitude}&longitude=${position.longitude}',
      );
      location = ActiveLocation.fromJson(
        Map<String, dynamic>.from(result['location'] as Map),
      );
      location = ActiveLocation(
        addressId: null,
        formattedAddress: location.formattedAddress,
        city: location.city,
        state: location.state,
        postalCode: location.postalCode,
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'gps',
        placeId: location.placeId,
      );
    } on AuthApiException catch (error) {
      if (error.statusCode != 503) rethrow;
      location = ActiveLocation(
        addressId: null,
        formattedAddress:
            'Current location · ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
        city: '',
        state: '',
        postalCode: '',
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'gps',
      );
    }
    await selectLocation(location);
  }

  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    final result = await auth.getAuthenticated(
      '/api/location/autocomplete?q=${Uri.encodeQueryComponent(query)}',
    );
    return (result['suggestions'] as List)
        .map(
          (value) =>
              PlaceSuggestion.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
  }

  Future<ActiveLocation> resolveSuggestion(PlaceSuggestion suggestion) async {
    final result = await auth.getAuthenticated(
      '/api/location/places/${Uri.encodeComponent(suggestion.placeId)}',
    );
    final location = ActiveLocation.fromJson(
      Map<String, dynamic>.from(result['location'] as Map),
    );
    final selectedLocation = ActiveLocation(
      addressId: null,
      formattedAddress: location.formattedAddress,
      city: location.city,
      state: location.state,
      postalCode: location.postalCode,
      latitude: location.latitude,
      longitude: location.longitude,
      source: 'manual',
      placeId: suggestion.placeId,
    );
    await selectLocation(selectedLocation);
    return selectedLocation;
  }

  Future<SavedAddress> saveAddress(SavedAddress address) async {
    final result = await auth.postAuthenticated(
      '/api/addresses',
      address.toPayload(),
    );
    final saved = SavedAddress.fromJson(
      Map<String, dynamic>.from(result['address'] as Map),
    );
    addresses = [...addresses.where((value) => value.id != saved.id), saved];
    notifyListeners();
    return saved;
  }

  Future<SavedAddress> updateAddress(SavedAddress address) async {
    final result = await auth.putAuthenticated(
      '/api/addresses/${address.id}',
      address.toPayload(),
    );
    final updated = SavedAddress.fromJson(
      Map<String, dynamic>.from(result['address'] as Map),
    );
    addresses = addresses
        .map((value) => value.id == updated.id ? updated : value)
        .toList();
    if (selected?.addressId == updated.id) {
      selected = ActiveLocation(
        addressId: updated.id,
        formattedAddress: updated.formattedAddress,
        city: updated.city,
        state: updated.state,
        postalCode: updated.postalCode,
        latitude: updated.latitude!,
        longitude: updated.longitude!,
        source: 'saved',
        placeId: updated.placeId,
      );
      await auth.putAuthenticated('/api/location', {'address_id': updated.id});
    }
    notifyListeners();
    return updated;
  }

  Future<void> deleteAddress(SavedAddress address) async {
    await auth.deleteAuthenticated('/api/addresses/${address.id}');
    addresses = addresses.where((value) => value.id != address.id).toList();
    if (selected?.addressId == address.id) {
      selected = ActiveLocation(
        addressId: null,
        formattedAddress: address.formattedAddress,
        city: address.city,
        state: address.state,
        postalCode: address.postalCode,
        latitude: address.latitude!,
        longitude: address.longitude!,
        source: 'manual',
        placeId: address.placeId,
      );
    }
    notifyListeners();
  }

  Future<void> makeDefault(SavedAddress address) async {
    final result = await auth.postAuthenticated(
      '/api/addresses/${address.id}/default',
      {},
    );
    final updated = SavedAddress.fromJson(
      Map<String, dynamic>.from(result['address'] as Map),
    );
    addresses = addresses
        .map(
          (value) => value.id == updated.id
              ? updated
              : SavedAddress(
                  id: value.id,
                  label: value.label,
                  houseNumber: value.houseNumber,
                  street: value.street,
                  area: value.area,
                  city: value.city,
                  state: value.state,
                  postalCode: value.postalCode,
                  formattedAddress: value.formattedAddress,
                  latitude: value.latitude,
                  longitude: value.longitude,
                  placeId: value.placeId,
                  isDefault: false,
                ),
        )
        .toList();
    notifyListeners();
  }

  Future<List<NearbyProvider>> nearbyProviders({
    required String category,
    required double radiusKm,
    bool availableOnly = false,
  }) async {
    final location = selected;
    if (location == null) {
      throw const AuthApiException(
        'Select a location with coordinates to find nearby providers.',
      );
    }
    final query = {
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'category': category,
      'available': availableOnly ? 'true' : 'false',
      'radius': radiusKm.toStringAsFixed(0),
      'sort': 'nearest',
    };
    final uri = Uri(path: '/api/providers/nearby', queryParameters: query);
    final result = await auth.getAuthenticated(uri.toString());
    return (result['providers'] as List)
        .map(
          (value) =>
              NearbyProvider.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
  }
}
