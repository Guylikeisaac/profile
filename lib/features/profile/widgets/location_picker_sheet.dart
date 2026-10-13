import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/resume_sections_repository.dart';
import '../providers/profile_provider.dart';
import 'profile_sheet_kit.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';

/// Opens the reusable location search picker and returns the chosen
/// [LocationOption] (or null if dismissed). Backed by
/// `GET /resume-service/locations`, so it supplies the `locationId` that the
/// experience/education/current-location endpoints want.
Future<LocationOption?> showLocationPicker(BuildContext context) {
  return showProfileSheet<LocationOption>(
    context,
    fullHeight: true,
    builder: (_) => const _LocationPickerSheet(),
  );
}

class _LocationPickerSheet extends ConsumerStatefulWidget {
  const _LocationPickerSheet();

  @override
  ConsumerState<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<LocationOption> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    _lastQuery = q;
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final res =
        await ref.read(resumeSectionsRepositoryProvider).searchLocations(q);
    if (!mounted || q != _lastQuery) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return ProfileSheetScaffold(
      title: 'Location',
      icon: Icons.location_on_outlined,
      tintedIcon: true,
      fullHeight: true,
      subtitle: 'Search a city, state or country',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTextField(
            label: 'Search',
            hint: 'e.g. Bengaluru, Maharashtra…',
            controller: _query,
            leadingIcon: Icons.search,
            onChanged: _onChanged,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_results.isEmpty && _query.text.trim().length >= 2)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No matching locations.',
                  style: TextStyle(fontSize: 13.5, color: tokens.textTertiary)),
            )
          else
            for (final loc in _results)
              _LocationTile(
                label: loc.label,
                onTap: () => Navigator.of(context).pop(loc),
              ),
        ],
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined,
                size: 18, color: context.tokensOrDefault.iconInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  color: colors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
