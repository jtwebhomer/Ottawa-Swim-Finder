import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

/// Lightweight first-run welcome — no network sync required.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final freshness = state.syncFreshness;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.pool,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Ottawa Swim Finder',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Browse ${state.onboardingFacilityCount} pools and '
                '${state.onboardingSessionCount} upcoming swims instantly — '
                'no download required.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                freshness != null
                    ? '${freshness.completenessLabel} from bundled data. '
                        'Live schedules refresh quietly in the background.'
                    : 'Bundled schedules are ready offline. Live updates run in the background.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (state.isSyncing) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  state.syncMessage ?? 'Updating schedules in background…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: () => state.completeWelcome(),
                child: const Text('Start Exploring'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
