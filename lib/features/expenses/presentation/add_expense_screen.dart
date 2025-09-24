import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../groups/domain/group_controller.dart';
import '../../groups/domain/group_model.dart';
import '../domain/expense_controller.dart';
import '../domain/expense_model.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? initialGroupId; // If provided, lock to this group context
  final ExpenseModel? editingExpense; // If provided, screen works in edit mode
  const AddExpenseScreen({super.key, this.initialGroupId, this.editingExpense});

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
  bool _equalSplit = true; // true = equal split, false = unequal split (only when customSplit is true)
  Map<String, double> _customAmounts = {}; // userId -> custom amount

  @override
  void initState() {
    super.initState();
    final e = widget.editingExpense;
    if (e != null) {
      _titleController.text = e.title;
      _amountController.text = e.amount.toStringAsFixed(2);
      _descriptionController.text = e.description;
      _selectedCategory = ExpenseCategory.values.firstWhere(
        (c) => c.name == e.category,
        orElse: () => ExpenseCategory.other,
      );
      _selectedDate = e.date;
      _selectedGroupId = e.groupId == 'personal' ? null : e.groupId;
      _customSplit = true;
      _selectedMemberIds = e.splitBetween.toSet();
      _customAmounts = Map<String, double>.from(e.customAmounts);
      _equalSplit = e.customAmounts.isEmpty; // If no custom amounts, it was equal split
    }
  }

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authControllerProvider).value;
      if (user == null) throw Exception('User not found');

      final amount = double.parse(_amountController.text);
      
      // Determine split members and custom amounts
      List<String> splitBetween;
      Map<String, double> customAmounts = {};
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
          
          // Handle unequal split
          if (!_equalSplit) {
            // Validate custom amounts
            double totalCustomAmount = 0;
            for (final memberId in splitBetween) {
              final amount = _customAmounts[memberId] ?? 0;
              if (amount <= 0) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter valid amounts for all selected members')),
                  );
                }
                return;
              }
              totalCustomAmount += amount;
              customAmounts[memberId] = amount;
            }
            
            // Validate total matches expense amount
            if ((totalCustomAmount - amount).abs() > 0.01) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Total custom amounts (₹${totalCustomAmount.toStringAsFixed(2)}) must equal expense amount (₹${amount.toStringAsFixed(2)})')),
                );
              }
              return;
            }
          }
        } else {
          splitBetween = allMembers;
        }
        if (splitBetween.isEmpty) splitBetween = [user.id];
      }

      if (widget.editingExpense == null) {
        final expense = ExpenseModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: _titleController.text.trim(),
          amount: amount,
          category: _selectedCategory.name,
          description: _descriptionController.text.trim(),
          paidBy: user.id, // Store user ID instead of name for consistency
          splitBetween: splitBetween,
          date: _selectedDate,
          groupId: effectiveGroupId ?? 'personal',
          isSettled: false,
          customAmounts: customAmounts,
        );
        await ref.read(expenseControllerProvider.notifier).addExpense(expense);
      } else {
        final updated = widget.editingExpense!.copyWith(
          title: _titleController.text.trim(),
          amount: amount,
          category: _selectedCategory.name,
          description: _descriptionController.text.trim(),
          splitBetween: splitBetween,
          date: _selectedDate,
          groupId: effectiveGroupId ?? 'personal',
          customAmounts: customAmounts,
        );
        await ref.read(expenseControllerProvider.notifier).updateExpense(updated);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.editingExpense == null ? 'Expense added successfully!' : 'Expense updated')),
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
                                  onSelectionChanged: (s) {
                                    setState(() {
                                      _customSplit = s.first;
                                      if (!_customSplit) {
                                        // Reset to equal split mode
                                        _selectedMemberIds = members.toSet();
                                        _customAmounts.clear();
                                        _equalSplit = true;
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                
                                // Equal split mode
                                if (!_customSplit) ...[
                                  Wrap(
                                    spacing: 8,
                                    children: members.map((id) {
                                      final isCurrentUser = auth != null && id == auth.id;
                                      final name = isCurrentUser ? 'You' : group.getMemberName(id);
                                      return FilterChip(
                                        label: Text(name),
                                        selected: true,
                                        onSelected: null, // Cannot deselect in equal mode
                                      );
                                    }).toList(),
                                  ),
                                ] else ...[
                                  // Custom split mode
                                  // Equal/Unequal toggle
                                  SegmentedButton<bool>(
                                    segments: const [
                                      ButtonSegment(value: true, label: Text('Equal')),
                                      ButtonSegment(value: false, label: Text('Unequal')),
                                    ],
                                    selected: {_equalSplit},
                                    onSelectionChanged: (s) {
                                      setState(() {
                                        _equalSplit = s.first;
                                        if (_equalSplit) {
                                          _customAmounts.clear();
                                        } else {
                                          // Initialize custom amounts for selected members
                                          for (final id in _selectedMemberIds) {
                                            if (!_customAmounts.containsKey(id)) {
                                              _customAmounts[id] = 0;
                                            }
                                          }
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  
                                  // Member selection
                                  Wrap(
                                    spacing: 8,
                                    children: members.map((id) {
                                      final isCurrentUser = auth != null && id == auth.id;
                                      final name = isCurrentUser ? 'You' : group.getMemberName(id);
                                      final selected = _selectedMemberIds.contains(id);
                                      return FilterChip(
                                        label: Text(name),
                                        selected: selected,
                                        onSelected: (val) {
                                          setState(() {
                                            if (val) {
                                              _selectedMemberIds.add(id);
                                              if (!_equalSplit) {
                                                _customAmounts[id] = 0;
                                              }
                                            } else {
                                              _selectedMemberIds.remove(id);
                                              _customAmounts.remove(id);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  // Quick selection buttons
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _selectedMemberIds = members.toSet();
                                            if (!_equalSplit) {
                                              for (final id in members) {
                                                _customAmounts[id] = _customAmounts[id] ?? 0;
                                              }
                                            }
                                          });
                                        },
                                        child: const Text('Select all'),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _selectedMemberIds = {auth?.id ?? ''};
                                            if (!_equalSplit) {
                                              _customAmounts.clear();
                                              _customAmounts[auth?.id ?? ''] = 0;
                                            }
                                          });
                                        },
                                        child: const Text('Only me'),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _selectedMemberIds.remove(auth?.id ?? '');
                                            _customAmounts.remove(auth?.id ?? '');
                                          });
                                        },
                                        child: const Text('Exclude me'),
                                      ),
                                    ],
                                  ),
                                  
                                  // Custom amount inputs for unequal split
                                  if (!_equalSplit && _selectedMemberIds.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      'Enter amounts for each member:',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 8),
                                    ..._selectedMemberIds.map((id) {
                                      final isCurrentUser = auth != null && id == auth.id;
                                      final name = isCurrentUser ? 'You' : group.getMemberName(id);
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: TextFormField(
                                          initialValue: _customAmounts[id]?.toString() ?? '',
                                          decoration: InputDecoration(
                                            labelText: '$name (₹)',
                                            border: const OutlineInputBorder(),
                                            prefixText: '₹ ',
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (value) {
                                            final amount = double.tryParse(value) ?? 0;
                                            _customAmounts[id] = amount;
                                          },
                                          validator: (value) {
                                            if (!_equalSplit && _selectedMemberIds.contains(id)) {
                                              final amount = double.tryParse(value ?? '');
                                              if (amount == null || amount <= 0) {
                                                return 'Enter valid amount';
                                              }
                                            }
                                            return null;
                                          },
                                        ),
                                      );
                                    }).toList(),
                                    
                                    // Total validation display
                                    if (_customAmounts.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceVariant,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Total:'),
                                            Text(
                                              '₹${_customAmounts.values.fold(0.0, (sum, amount) => sum + amount).toStringAsFixed(2)}',
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
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
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.editingExpense == null ? 'Add Expense' : 'Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

