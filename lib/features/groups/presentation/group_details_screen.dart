import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../domain/group_controller.dart';
import '../domain/group_model.dart';

class GroupDetailsScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends ConsumerState<GroupDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  bool _saving = false;

  GroupModel? _group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await ref.read(groupControllerProvider.notifier).getGroup(widget.groupId);
    if (mounted) {
      setState(() {
        _group = g;
        _nameController.text = g?.name ?? '';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _group == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(groupControllerProvider.notifier).updateGroup(
            groupId: widget.groupId,
            name: _nameController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group updated')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    final isAdmin = user != null && _group?.isAdmin(user.id) == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Details'),
      ),
      body: _group == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                        border: OutlineInputBorder(),
                      ),
                      enabled: isAdmin,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Members (${_group!.memberUserIds.length})', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _group!.memberUserIds.length,
                      itemBuilder: (context, index) {
                        final id = _group!.memberUserIds[index];
                        final canRemove = isAdmin && id != _group!.createdByUserId;
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(_group!.getMemberName(id)),
                          subtitle: Text(id),
                          trailing: canRemove
                              ? IconButton(
                                  icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                                  tooltip: 'Remove member',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Remove member'),
                                        content: Text('Remove ${_group!.getMemberName(id)} from the group?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                            child: const Text('Remove'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;
                                    try {
                                      await ref
                                          .read(groupControllerProvider.notifier)
                                          .removeMemberFromGroup(widget.groupId, id);
                                      await _load();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Member removed')),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to remove member: $e')),
                                        );
                                      }
                                    }
                                  },
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  if (isAdmin)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}


