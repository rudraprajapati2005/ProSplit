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
                    onLongPress: isAdmin
                        ? () async {
                            final textController = TextEditingController();
                            final proceed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Are you sure you want to delete group?'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('This will archive the group and delete all its expenses.'),
                                    const SizedBox(height: 8),
                                    const Text('Type "confirm" to proceed:'),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: textController,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'confirm',
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                  TextButton(
                                    onPressed: () {
                                      if (textController.text.trim().toLowerCase() == 'confirm') {
                                        Navigator.of(ctx).pop(true);
                                      }
                                    },
                                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (proceed == true) {
                              try {
                                await ref.read(groupControllerProvider.notifier).deleteGroup(g.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group deleted')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete group: $e')));
                                }
                              }
                            }
                          }
                        : null,
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
  List<_UserSuggestion> suggestions = [];
  Set<String> selectedUserIds = {};
  Map<String, String> selectedUserNames = {};
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

        void toggleUser(_UserSuggestion user) {
          setState(() {
            if (selectedUserIds.contains(user.id)) {
              selectedUserIds.remove(user.id);
              selectedUserNames.remove(user.id);
            } else {
              selectedUserIds.add(user.id);
              selectedUserNames[user.id] = user.label.split(' • ').first;
            }
          });
        }

        return AlertDialog(
          title: const Text('Add Members'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search by name, email or ID',
                      prefixIcon: Icon(Icons.search),
                    ),
                    autofocus: true,
                    onChanged: (v) {
                      if (v.trim().length >= 2) {
                        runSearch(v.trim());
                      } else {
                        setState(() { suggestions = []; });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  // Selected members
                  if (selectedUserIds.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Selected Members:', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: selectedUserIds.map((userId) {
                        final name = selectedUserNames[userId] ?? 'Unknown';
                        return Chip(
                          label: Text(name),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => toggleUser(_UserSuggestion(id: userId, label: name)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Search results
                  SizedBox(
                    height: 200,
                    child: isSearching
                        ? const Center(child: CircularProgressIndicator())
                        : suggestions.isEmpty
                            ? const Center(child: Text('No users found'))
                            : ListView.builder(
                                itemCount: suggestions.length,
                                itemBuilder: (c, i) {
                                  final s = suggestions[i];
                                  final isSelected = selectedUserIds.contains(s.id);
                                  return ListTile(
                                    dense: true,
                                    title: Text(s.label),
                                    leading: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => toggleUser(s),
                                    ),
                                    onTap: () => toggleUser(s),
                                  );
                                },
                              ),
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
              onPressed: selectedUserIds.isEmpty ? null : () async {
                try {
                  for (final userId in selectedUserIds) {
                    final userName = selectedUserNames[userId] ?? 'Unknown User';
                    await ref.read(groupControllerProvider.notifier)
                        .addMemberToGroup(groupId, userId, userName);
                  }
                  if (context.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${selectedUserIds.length} member(s) added')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to add members: $e')),
                    );
                  }
                }
              },
              child: Text('Add ${selectedUserIds.length} Member(s)'),
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

