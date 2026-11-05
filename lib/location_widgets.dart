import 'dart:async';

import 'package:flutter/material.dart';

import 'location_service.dart';

const _blue = Color(0xFF2878E5);
const _ink = Color(0xFF172B4D);
const _muted = Color(0xFF718096);

class LocationSelector extends StatelessWidget {
  final LocationService locations;
  final bool compact;

  const LocationSelector({
    super.key,
    required this.locations,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: locations,
    builder: (context, _) {
      final selected = locations.selected;
      final text = selected == null || selected.formattedAddress.isEmpty
          ? 'Select your location'
          : selected.formattedAddress;
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => LocationPickerSheet(locations: locations),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 3 : 7),
          child: Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                color: _blue,
                size: compact ? 22 : 18,
              ),
              SizedBox(width: compact ? 8 : 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, color: _muted),
            ],
          ),
        ),
      );
    },
  );
}

class LocationPickerSheet extends StatefulWidget {
  final LocationService locations;
  const LocationPickerSheet({super.key, required this.locations});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final search = TextEditingController();
  Timer? debounce;
  List<PlaceSuggestion> suggestions = const [];
  bool searching = false, usingGps = false;
  String? searchError;

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _search(String value) {
    debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        suggestions = const [];
        searchError = null;
        searching = false;
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        searching = true;
        searchError = null;
      });
      try {
        final results = await widget.locations.autocomplete(value.trim());
        if (!mounted) return;
        setState(() => suggestions = results);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          suggestions = const [];
          searchError = error.toString();
        });
      } finally {
        if (mounted) setState(() => searching = false);
      }
    });
  }

  Future<void> _useGps() async {
    setState(() {
      usingGps = true;
      searchError = null;
    });
    try {
      await widget.locations.useCurrentLocation();
      if (!mounted) return;
      final selected = widget.locations.selected;
      Navigator.pop(context);
      if (selected?.formattedAddress.startsWith('Current location ·') ??
          false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS coordinates saved. Add a Google Geocoding key to show a readable address.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => searchError = error.toString());
    } finally {
      if (mounted) setState(() => usingGps = false);
    }
  }

  Future<void> _chooseSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      await widget.locations.resolveSuggestion(suggestion);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => searchError = error.toString());
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _addManualAddress() async {
    final saved = await showDialog<SavedAddress>(
      context: context,
      builder: (_) => const AddressEditorDialog(),
    );
    if (saved == null) return;
    try {
      final created = await widget.locations.saveAddress(saved);
      await widget.locations.selectAddress(created);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => searchError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Location',
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
                fontSize: 21,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: search,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Search area, city or address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (suggestions.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  'Powered by Google',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ),
            if (searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  searchError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            if (suggestions.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = suggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined, color: _blue),
                      title: Text(
                        suggestion.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _chooseSuggestion(suggestion),
                    );
                  },
                ),
              ),
            if (suggestions.isEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: usingGps ? null : _useGps,
                  icon: usingGps
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    usingGps
                        ? 'Detecting current location…'
                        : 'Use Current Location',
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Text(
                  'Saved Locations',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.locations,
                  builder: (context, _) => ListView(
                    children: [
                      ...widget.locations.addresses.map(
                        (address) => ListTile(
                          leading: Icon(
                            address.label == 'Home'
                                ? Icons.home_outlined
                                : address.label == 'Work'
                                ? Icons.work_outline
                                : Icons.place_outlined,
                            color: _blue,
                          ),
                          title: Text(
                            '${address.label}${address.isDefault ? ' · Default' : ''}',
                          ),
                          subtitle: Text(
                            address.formattedAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing:
                              widget.locations.selected?.addressId == address.id
                              ? const Icon(Icons.check_circle, color: _blue)
                              : null,
                          onTap: () async {
                            try {
                              await widget.locations.selectAddress(address);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                            } catch (error) {
                              if (mounted) {
                                setState(() => searchError = error.toString());
                              }
                            }
                          },
                        ),
                      ),
                      if (widget.locations.addresses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'No saved locations yet.',
                            style: TextStyle(color: _muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addManualAddress,
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Address'),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class AddressEditorDialog extends StatefulWidget {
  final SavedAddress? address;
  const AddressEditorDialog({super.key, this.address});

  @override
  State<AddressEditorDialog> createState() => _AddressEditorDialogState();
}

class _AddressEditorDialogState extends State<AddressEditorDialog> {
  final form = GlobalKey<FormState>();
  late final controllers = <String, TextEditingController>{
    'house_number': TextEditingController(
      text: widget.address?.houseNumber ?? '',
    ),
    'street': TextEditingController(text: widget.address?.street ?? ''),
    'area': TextEditingController(text: widget.address?.area ?? ''),
    'city': TextEditingController(text: widget.address?.city ?? ''),
    'state': TextEditingController(text: widget.address?.state ?? ''),
    'postal_code': TextEditingController(
      text: widget.address?.postalCode ?? '',
    ),
    'formatted_address': TextEditingController(
      text: widget.address?.formattedAddress ?? '',
    ),
    'latitude': TextEditingController(
      text: widget.address?.latitude?.toString() ?? '',
    ),
    'longitude': TextEditingController(
      text: widget.address?.longitude?.toString() ?? '',
    ),
  };
  late String label = widget.address?.label ?? 'Home';
  late bool isDefault = widget.address?.isDefault ?? false;

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String value(String key) => controllers[key]!.text.trim();

  void _save() {
    if (!(form.currentState?.validate() ?? false)) return;
    final address = SavedAddress(
      id: widget.address?.id ?? 0,
      label: label,
      houseNumber: value('house_number'),
      street: value('street'),
      area: value('area'),
      city: value('city'),
      state: value('state'),
      postalCode: value('postal_code'),
      formattedAddress: value('formatted_address').isEmpty
          ? [
              value('house_number'),
              value('street'),
              value('area'),
              value('city'),
              value('state'),
              value('postal_code'),
            ].where((part) => part.isNotEmpty).join(', ')
          : value('formatted_address'),
      latitude: value('latitude').isEmpty
          ? null
          : double.tryParse(value('latitude')),
      longitude: value('longitude').isEmpty
          ? null
          : double.tryParse(value('longitude')),
      placeId: widget.address?.placeId,
      isDefault: isDefault,
    );
    if ((address.latitude == null) != (address.longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both latitude and longitude.')),
      );
      return;
    }
    Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.address == null ? 'Add saved address' : 'Edit saved address',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: label,
                decoration: const InputDecoration(labelText: 'Label'),
                items: const ['Home', 'Work', 'Other']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => label = value ?? label),
              ),
              _field('house_number', 'House / Flat Number'),
              _field('street', 'Street'),
              _field('area', 'Area / Locality'),
              _field('city', 'City', requiredField: true),
              _field('state', 'State'),
              _field('postal_code', 'PIN Code'),
              _field('formatted_address', 'Complete address'),
              _field(
                'latitude',
                'Latitude (required without Google Geocoding)',
                keyboard: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              _field(
                'longitude',
                'Longitude',
                keyboard: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set as default'),
                value: isDefault,
                onChanged: (value) => setState(() => isDefault = value),
              ),
              const Text(
                'With Google Geocoding configured, leave coordinates blank and they will be resolved from the address. Without it, enter coordinates to enable nearby search.',
                style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  Widget _field(
    String key,
    String label, {
    bool requiredField = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: TextFormField(
      controller: controllers[key],
      keyboardType: keyboard,
      onChanged: (text) {
        if (const {
              'house_number',
              'street',
              'area',
              'city',
              'state',
              'postal_code',
              'formatted_address',
            }.contains(key) &&
            widget.address != null) {
          controllers['latitude']!.clear();
          controllers['longitude']!.clear();
        }
      },
      decoration: InputDecoration(labelText: label),
      validator: (text) {
        final trimmed = text?.trim() ?? '';
        if (requiredField && trimmed.isEmpty) return 'Required';
        if ((key == 'latitude' || key == 'longitude') &&
            trimmed.isNotEmpty &&
            double.tryParse(trimmed) == null) {
          return 'Enter a valid number';
        }
        return null;
      },
    ),
  );
}

class SavedAddressesScreen extends StatelessWidget {
  final LocationService locations;
  const SavedAddressesScreen({super.key, required this.locations});

  Future<void> _edit(BuildContext context, SavedAddress? existing) async {
    final address = await showDialog<SavedAddress>(
      context: context,
      builder: (_) => AddressEditorDialog(address: existing),
    );
    if (address == null) return;
    try {
      if (existing == null) {
        await locations.saveAddress(address);
      } else {
        await locations.updateAddress(address);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved Addresses')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(context, null),
      icon: const Icon(Icons.add),
      label: const Text('Add Address'),
    ),
    body: AnimatedBuilder(
      animation: locations,
      builder: (context, _) {
        if (locations.loading && locations.addresses.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (locations.addresses.isEmpty) {
          return const Center(
            child: Text(
              'No saved addresses. Add one to use it across the app.',
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: locations.addresses
              .map(
                (address) => Card(
                  child: ListTile(
                    leading: Icon(
                      address.label == 'Home'
                          ? Icons.home_outlined
                          : address.label == 'Work'
                          ? Icons.work_outline
                          : Icons.place_outlined,
                      color: _blue,
                    ),
                    title: Text(
                      '${address.label}${address.isDefault ? ' · Default' : ''}',
                    ),
                    subtitle: Text(
                      '${address.formattedAddress}\n${address.latitude}, ${address.longitude}',
                    ),
                    isThreeLine: true,
                    onTap: () async {
                      try {
                        await locations.selectAddress(address);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Location selected for Home, Search and Map.',
                              ),
                            ),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        try {
                          if (action == 'edit') await _edit(context, address);
                          if (action == 'default') {
                            await locations.makeDefault(address);
                          }
                          if (action == 'delete') {
                            await locations.deleteAddress(address);
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'default',
                          child: Text('Set default'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
