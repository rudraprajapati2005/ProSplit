import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../groups/domain/group_controller.dart';
import '../../groups/domain/group_model.dart';
import '../domain/expense_controller.dart';
import '../domain/expense_model.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? initialGroupId; // If provided, lock to this group context
  const AddExpenseScreen({super.key, this.initialGroupId});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  ExpenseCategory _selectedCategory = ExpenseCategory.food;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  String? _selectedGroupId; // null for personal
  Set<String> _selectedMemberIds = {};
  bool _customSplit = false; // false = equal, true = custom subset

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authControllerProvider).value;
      if (user == null) throw Exception('User not found');

      final amount = double.parse(_amountController.text);
      
      // Determine split members (equal or custom subset)
      List<String> splitBetween;
      final effectiveGroupId = widget.initialGroupId ?? _selectedGroupId;
      if (effectiveGroupId == null) {
        splitBetween = [user.id];
      } else {
        final group = await ref.read(groupControllerProvider.notifier).getGroup(effectiveGroupId);
        final allMembers = group == null ? <String>[user.id] : group.allMemberIds;
        if (_customSplit) {
          if (_selectedMemberIds.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select at least one participant for custom split')),
              );
            }
            return;
          }
          splitBetween = _selectedMemberIds.toList();
        } else {
          splitBetween = allMembers;
        }
        if (splitBetween.isEmpty) splitBetween = [user.id];
      }

      final expense = ExpenseModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        amount: amount,
        category: _selectedCategory.name,
        description: _descriptionController.text.trim(),
        paidBy: user.name,
        splitBetween: splitBetween,
        date: _selectedDate,
        groupId: effectiveGroupId ?? 'personal',
        isSettled: false,
      );

      await ref.read(expenseControllerProvider.notifier).addExpense(expense);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding expense: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).value;
    final groupsAsync = ref.watch(groupControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group selector
              groupsAsync.when(
                data: (groups) {
                  final items = [
                    const DropdownMenuItem<String?>(value: null, child: Text('Personal')),
                    ...groups.map((g) => DropdownMenuItem<String?>(value: g.id, child: Text(g.name))),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String?>(
                        value: widget.initialGroupId ?? _selectedGroupId,
                        decoration: const InputDecoration(
                          labelText: 'Charge to',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.group_add),
                        ),
                        items: items,
                        onChanged: widget.initialGroupId != null
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedGroupId = value;
                                  _selectedMemberIds.clear();
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      if ((widget.initialGroupId ?? _selectedGroupId) != null)
                        Builder(
                          builder: (_) {
                            final gid = widget.initialGroupId ?? _selectedGroupId;
                            final group = groups.firstWhere((g) => g.id == gid);
                            final members = group.allMemberIds;
                            final title = Text('Split', style: Theme.of(context).textTheme.titleMedium);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 8),
                                SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(value: false, label: Text('Equal')),
                                    ButtonSegment(value: true, label: Text('Custom')),
                                  ],
                                  selected: {_customSplit},
                                  onSelectionChanged: (s) => setState(() => _customSplit = s.first),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: members.map((id) {
                                    final name = group.getMemberName(id);
                                    final selected = _customSplit
                                        ? _selectedMemberIds.contains(id)
                                        : true; // equal mode shows all as selected
                                    return FilterChip(
                                      label: Text(name),
                                      selected: selected,
                                      onSelected: _customSplit
                                          ? (val) {
                                              setState(() {
                                                if (val) {
                                                  _selectedMemberIds.add(id);
                                                } else {
                                                  _selectedMemberIds.remove(id);
                                                }
                                              });
                                            }
                                          : null,
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                if (_customSplit)
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() => _selectedMemberIds = members.toSet());
                                        },
                                        child: const Text('Select all'),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () {
                                          setState(() => _selectedMemberIds = {auth?.id ?? ''});
                                        },
                                        child: const Text('Only me'),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () {
                                          setState(() => _selectedMemberIds.remove(auth?.id ?? ''));
                                        },
                                        child: const Text('Exclude me'),
                                      ),
                                    ],
                                  )
                              ],
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
              ),
              // Title Field
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Expense Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an expense title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Amount Field
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  if (double.parse(value) <= 0) {
                    return 'Amount must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Category Dropdown
              DropdownButtonFormField<ExpenseCategory>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: ExpenseCategory.values.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Row(
                      children: [
                        Icon(category.icon),
                        const SizedBox(width: 8),
                        Text(category.displayName),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Date Picker
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              // Add Expense Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _addExpense,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add Expense'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

