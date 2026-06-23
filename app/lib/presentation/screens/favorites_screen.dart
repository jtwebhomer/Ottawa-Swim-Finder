import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'facility_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final favorites = state.facilities.where((f) => f.isFavorite).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: favorites.isEmpty
          ? const Center(child: Text('No favorite facilities yet'))
          : ListView.builder(
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final facility = favorites[index];
                return ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.red),
                  title: Text(facility.name),
                  subtitle: Text(facility.address ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.favorite),
                    onPressed: () => state.toggleFavorite(facility),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FacilityScreen(facilityId: facility.id),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
