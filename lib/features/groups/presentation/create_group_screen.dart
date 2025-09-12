import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/auth_controller.dart';
import '../domain/group_controller.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  bool _isLoading = false;
  List<String> _invitedEmails = [];
  List<String> _suggestedEmails = [];
  List<String> _allUserEmails = [];
  bool _isLoadingEmails = true;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailChanged);
    _loadUserEmails();
  }

  Future<void> _loadUserEmails() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      
      setState(() {
        _allUserEmails = snapshot.docs
            .map((doc) => doc.data()['email'] as String? ?? '')
            .where((email) => email.isNotEmpty)
            .toList();
        _isLoadingEmails = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingEmails = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    final query = _emailController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _suggestedEmails = []);
      return;
    }
    
    setState(() {
      _suggestedEmails = _allUserEmails
          .where((email) => 
              email.toLowerCase().contains(query) && 
              !_invitedEmails.contains(email))
          .take(5)
          .toList();
    });
  }

  void _addEmail(String email) {
    if (email.isNotEmpty && !_invitedEmails.contains(email)) {
      setState(() {
        _invitedEmails.add(email);
        _emailController.clear();
        _suggestedEmails.clear();
      });
    }
  }

  void _removeEmail(String email) {
    setState(() {
      _invitedEmails.remove(email);
    });
  }

  void _addEmailFromText() {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && email.contains('@') && !_invitedEmails.contains(email)) {
      _addEmail(email);
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authControllerProvider).value;
      if (user == null) throw Exception('User not found');
      
      await ref.read(groupControllerProvider.notifier).createGroup(
            name: _nameController.text.trim(),
            creatorUserId: user.id,
            inviteEmails: _invitedEmails,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Group created')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Group')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Name Field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter group name'
                    : null,
              ),
              const SizedBox(height: 24),

              // Invited Emails Section
              const Text(
                'Invite Members',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Email Input with Suggestions
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Enter email address',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email),
                      suffixIcon: _emailController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addEmailFromText,
                            )
                          : null,
                    ),
                    onFieldSubmitted: (_) => _addEmailFromText(),
                  ),
                  
                  // Email Suggestions
                  if (_isLoadingEmails)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Loading users...'),
                        ],
                      ),
                    )
                  else if (_suggestedEmails.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _suggestedEmails.length,
                        itemBuilder: (context, index) {
                          final email = _suggestedEmails[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_add, size: 20),
                            title: Text(email),
                            onTap: () => _addEmail(email),
                          );
                        },
                      ),
                    )
                  else if (_emailController.text.isNotEmpty && _suggestedEmails.isEmpty && !_isLoadingEmails)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'No users found with this email',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Invited Emails Tags
              if (_invitedEmails.isNotEmpty) ...[
                const Text(
                  'Invited Members:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _invitedEmails.map((email) {
                    return Chip(
                      label: Text(email),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => _removeEmail(email),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              const Spacer(),
              
              // Create Group Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _create,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


