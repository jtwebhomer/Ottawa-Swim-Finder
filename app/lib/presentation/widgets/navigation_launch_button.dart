import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/navigation_service.dart';
import '../../di/injection.dart';
import '../providers/app_state.dart';

class NavigationLaunchButton extends StatelessWidget {
  const NavigationLaunchButton({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.compact = false,
  });

  final double latitude;
  final double longitude;
  final String title;
  final bool compact;

  Future<void> _launch(BuildContext context) async {
    final nav = getIt<NavigationService>();
    final state = context.read<AppState>();

    try {
      await nav.showDirections(
        latitude: latitude,
        longitude: longitude,
        title: title,
        originLat: state.userLat,
        originLng: state.userLng,
        context: context,
      );
    } on NavigationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open navigation: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.navigation),
        tooltip: 'Navigate',
        onPressed: () => _launch(context),
      );
    }

    return FilledButton.icon(
      onPressed: () => _launch(context),
      icon: const Icon(Icons.navigation),
      label: const Text('Navigate'),
    );
  }
}
