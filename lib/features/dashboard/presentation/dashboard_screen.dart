import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return authState.when(
      data: (user) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                  ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ],
          ),
          body: const Center(
            child: Text('Welcome to your dashboard!'),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              // TODO: Navigate to create group screen
            },
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: NavigationBar(
            onDestinationSelected: (index) {
              // TODO: Implement navigation
            },
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.group),
                label: 'Groups',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet),
                label: 'Expenses',
              ),
              NavigationDestination(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text('Error: $error')),
    );
  }
}
