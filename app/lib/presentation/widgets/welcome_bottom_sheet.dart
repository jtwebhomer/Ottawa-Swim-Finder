import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

/// One-time welcome sheet — does not block app entry or require network.
Future<void> showWelcomeBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final state = ctx.watch<AppState>();
      return Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.pool,
              size: 56,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to Ottawa Swim Finder',
              style: Theme.of(ctx).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Browse ${state.onboardingFacilityCount} pools and find swims near you — '
              'works offline from day one.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Schedules refresh quietly in the background. Pull down on Home anytime to update.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                state.completeWelcome();
              },
              child: const Text('Get started'),
            ),
          ],
        ),
      );
    },
  );
}
