import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/group_controller.dart';
import 'create_group_screen.dart';
import 'group_expenses_screen.dart';
import 'group_details_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    final groupsState = ref.watch(groupControllerProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const Center(child: Text('User not found'));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Groups'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                  ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ],
          ),
          body: groupsState.when(
            data: (groups) {
              if (groups.isEmpty) {
                return const Center(child: Text('No groups yet'));
              }
              return ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final g = groups[index];
                  final currentUserId = user.id;
                  final isAdmin = g.createdByUserId == currentUserId;
                  return ListTile(
                    leading: const Icon(Icons.group),
                    title: Text(g.name),
                    subtitle: Text('${g.memberUserIds.length} members'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Group info',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupDetailsScreen(groupId: g.id),
                              ),
                            );
                          },
                        ),
                        if (isAdmin)
                          IconButton(
                            icon: const Icon(Icons.person_add_alt_1),
                            tooltip: 'Add member',
                            onPressed: () => _showAddMemberDialog(context, ref, g.id),
                          ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => GroupExpensesScreen(groupId: g.id),
                        ),
                      );
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              );
            },
            child: const Icon(Icons.add),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text('Error: $error')),
    );
  }
}

Future<void> _showAddMemberDialog(BuildContext context, WidgetRef ref, String groupId) async {
  final searchController = TextEditingController();
  final userNameController = TextEditingController();
  String? selectedUserId;
  List<_UserSuggestion> suggestions = [];
  bool isSearching = false;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        Future<void> runSearch(String q) async {
          setState(() { isSearching = true; });
          try {
            final repo = ref.read(authRepositoryProvider);
            final users = await repo.searchUsers(q);
            suggestions = users
                .map((u) => _UserSuggestion(id: u.id, label: '${u.name} • ${u.email}'))
                .toList();
          } catch (_) {
            suggestions = [];
          } finally {
            setState(() { isSearching = false; });
          }
        }
        return AlertDialog(
          title: const Text('Add Member'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(labelText: 'Search by name, email or ID'),
                    autofocus: true,
                    onChanged: (v) {
                      if (v.trim().length >= 2) {
                        runSearch(v.trim());
                      } else {
                        setState(() { suggestions = []; });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 140,
                    child: isSearching
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: suggestions.length,
                            itemBuilder: (c, i) {
                              final s = suggestions[i];
                              final selected = s.id == selectedUserId;
                              return ListTile(
                                dense: true,
                                title: Text(s.label),
                                trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                                onTap: () {
                                  selectedUserId = s.id;
                                  userNameController.text = s.label.split(' • ').first;
                                  setState(() {});
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: userNameController,
                    decoration: const InputDecoration(labelText: 'User name'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final userId = selectedUserId ?? searchController.text.trim();
              final userName = userNameController.text.trim();
              if (userId.isEmpty || userName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter both User ID and User name')),
                );
                return;
              }
              try {
                await ref.read(groupControllerProvider.notifier)
                    .addMemberToGroup(groupId, userId, userName);
                if (context.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Member added')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add member: $e')),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
          ],
        );
      });
    },
  );
}

class _UserSuggestion {
  final String id;
  final String label;
  _UserSuggestion({required this.id, required this.label});
}

