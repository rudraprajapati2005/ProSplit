import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/user_model.dart';
import '../../expenses/domain/expense_controller.dart';
import '../../expenses/domain/expense_model.dart';
import '../../expenses/presentation/add_expense_screen.dart';
import '../domain/group_controller.dart';
import '../domain/member_info.dart';
import 'group_settlements_screen.dart';

class GroupExpensesScreen extends ConsumerWidget {
  final String groupId;
  const GroupExpensesScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(groupExpensesProvider(groupId));
    final currentUser = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Expenses'),
        actions: [
          IconButton(
            tooltip: 'Settlements',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupSettlementsScreen(groupId: groupId),
                ),
              );
            },
          ),
        ],
      ),
      body: expensesAsync.when(
        data: (expenses) {
          final groupExpenses = expenses
            ..sort((a, b) => a.date.compareTo(b.date));
          if (groupExpenses.isEmpty) {
            return const Center(child: Text('No expenses yet. Add one!'));
          }
          // Settlement + chat-like list with date headers
          return FutureBuilder(
            future: ref.read(groupControllerProvider.notifier).getGroup(groupId),
            builder: (context, snapshot) {
              final group = snapshot.data;
              final memberNames = group?.memberNames ?? const <String, String>{};
              final members = group?.members;

              // Ensure member info is populated/migrated so names are available
              if (group != null) {
                if ((group.members).isEmpty && memberNames.isNotEmpty) {
                  // Migrate legacy names to new structure in background
                  ref.read(groupControllerProvider.notifier).migrateGroupToNewStructure(groupId);
                }

                final allMemberIds = <String>{group.createdByUserId}
                  ..addAll(group.memberUserIds);
                final hasIssues = allMemberIds.any((id) {
                  if (group.members.containsKey(id)) return false;
                  final name = memberNames[id];
                  return name == null || name.isEmpty || name == id || name.length > 20;
                });

                if (hasIssues) {
                  ref.read(groupControllerProvider.notifier).populateMissingMemberNames(groupId);
                }
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: groupExpenses.length,
                reverse: true, // Show most recent first
                itemBuilder: (context, index) {
                  // Reverse the index to show most recent first
                  final reversedIndex = groupExpenses.length - 1 - index;
                  final expense = groupExpenses[reversedIndex];
                  final isMine = expense.paidBy == (currentUser?.id ?? '');
                  final dateLabel = _formatDayLabel(expense.date);
                  final bool showHeader = index == 0 ||
                      _formatDayLabel(groupExpenses[groupExpenses.length - index].date) != dateLabel;

                  final bubble = Dismissible(
                    key: ValueKey('exp-${expense.id}'),
                    direction: DismissDirection.horizontal,
                    confirmDismiss: (_) async => false, // swipe to reveal timestamp only
                    background: _timestampBackground(context, expense.date, alignRight: false),
                    secondaryBackground: _timestampBackground(context, expense.date, alignRight: true),
                    child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isMine) _avatar(_getPaidByDisplayName(expense.paidBy, currentUser, memberNames, members: members)),
                      Flexible(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(isMine ? 12 : 2),
                              bottomRight: Radius.circular(isMine ? 2 : 12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      expense.title,
                                      style: Theme.of(context).textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.payments, size: 16),
                                      const SizedBox(width: 4),
                                  Text(
                                    '₹${expense.amount.toStringAsFixed(2)}',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Paid by ${_getPaidByDisplayName(expense.paidBy, currentUser, memberNames, members: members)}', style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              Text('Split among ${expense.splitBetween.length}', style: Theme.of(context).textTheme.bodySmall),
                              if (expense.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(expense.description, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (isMine) _avatar(_getPaidByDisplayName(expense.paidBy, currentUser, memberNames, members: members)),
                    ],
                    ),
                  );

                  if (showHeader) {
                    return Column(
                      children: [
                        const SizedBox(height: 6),
                        _dateHeader(context, dateLabel),
                        GestureDetector(
                          onTap: () => _showExpenseDetails(context, expense, currentUser, memberNames, members: members),
                          onLongPress: () => _showExpenseActions(context, ref, expense, groupId),
                          child: bubble,
                        ),
                      ],
                    );
                  }
                  return GestureDetector(
                    onTap: () => _showExpenseDetails(context, expense, currentUser, memberNames, members: members),
                    onLongPress: () => _showExpenseActions(context, ref, expense, groupId),
                    child: bubble,
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
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddExpenseScreen(initialGroupId: groupId),
            ),
          );
          // No need to refresh - the stream provider will automatically update
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

Widget _avatar(String name) {
  final initial = (name.isNotEmpty ? name.trim()[0] : '?').toUpperCase();
  return CircleAvatar(radius: 14, child: Text(initial));
}

Widget _dateHeader(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

String _formatDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  if (that == today) return 'Today';
  if (that == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${that.day}/${that.month}/${that.year}';
}

Widget _timestampBackground(BuildContext context, DateTime date, {required bool alignRight}) {
  final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return Container(
    color: Theme.of(context).colorScheme.surfaceVariant,
    alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        const Icon(Icons.schedule, size: 16),
        const SizedBox(width: 6),
        Text(time, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

Future<void> _showExpenseActions(BuildContext context, WidgetRef ref, ExpenseModel expense, String groupId) async {
  final user = ref.read(authControllerProvider).value;
  if (user == null) return;
  final group = await ref.read(groupControllerProvider.notifier).getGroup(groupId);
  final isGroupCreator = group?.createdByUserId == user.id;
  final isExpenseCreator = expense.paidBy == (user.name);
  final canModify = isGroupCreator || isExpenseCreator;
  if (!canModify) return;

  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit expense'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AddExpenseScreen(initialGroupId: expense.groupId == 'personal' ? null : expense.groupId, editingExpense: expense),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete expense'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('Delete expense?'),
                    content: const Text('This action cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(expenseControllerProvider.notifier).deleteExpense(expense.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense deleted')));
                  }
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

// Settlement helpers removed since settlements are shown on a dedicated screen now.

String _getPaidByDisplayName(String paidByUserId, UserModel? currentUser, Map<String, String> memberNames, {Map<String, MemberInfo>? members}) {
  if (currentUser != null && paidByUserId == currentUser.id) {
    return 'You';
  }
  // Prefer new members map
  if (members != null && members.containsKey(paidByUserId)) {
    final info = members[paidByUserId];
    if (info != null && info.username.isNotEmpty) return info.username;
  }
  // Fallback to legacy memberNames
  final name = memberNames[paidByUserId];
  if (name != null && name.isNotEmpty) return name;
  // If still not found but the id equals a value in memberNames (legacy name stored as id)
  final reverse = memberNames.entries.firstWhere(
    (e) => e.value == paidByUserId,
    orElse: () => const MapEntry('', ''),
  );
  if (reverse.key.isNotEmpty) return paidByUserId;
  // Shorten long Firebase UIDs
  if (paidByUserId.length > 20) return 'User ${paidByUserId.substring(0, 8)}...';
  return paidByUserId;
}

void _showExpenseDetails(BuildContext context, ExpenseModel expense, UserModel? currentUser, Map<String, String> memberNames, {Map<String, MemberInfo>? members}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(expense.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Amount
            _buildDetailRow(context, 'Amount', '₹${expense.amount.toStringAsFixed(2)}', Icons.payments),
            
            // Category
            _buildDetailRow(context, 'Category', _getCategoryDisplayName(expense.category), _getCategoryIcon(expense.category)),
            
            // Paid by
            _buildDetailRow(context, 'Paid by', _getPaidByDisplayName(expense.paidBy, currentUser, memberNames, members: members), Icons.person),
            
            // Date and time
            _buildDetailRow(context, 'Date', _formatDetailedDate(expense.date), Icons.calendar_today),
            _buildDetailRow(context, 'Time', _formatDetailedTime(expense.date), Icons.access_time),
            
            // Description
            if (expense.description.isNotEmpty)
              _buildDetailRow(context, 'Description', expense.description, Icons.description),
            
            const SizedBox(height: 16),
            
            // Split details
            Text(
              'Split Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            if (expense.customAmounts.isNotEmpty) ...[
              // Custom amounts
              ...expense.splitBetween.map((memberId) {
                final memberName = _getPaidByDisplayName(memberId, currentUser, memberNames, members: members);
                final amount = expense.customAmounts[memberId] ?? 0;
                return _buildSplitRow(context, memberName, '₹${amount.toStringAsFixed(2)}');
              }).toList(),
            ] else ...[
              // Equal split
              ...expense.splitBetween.map((memberId) {
                final memberName = _getPaidByDisplayName(memberId, currentUser, memberNames, members: members);
                final amount = expense.amount / expense.splitBetween.length;
                return _buildSplitRow(context, memberName, '₹${amount.toStringAsFixed(2)}');
              }).toList(),
            ],
            
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
                  Text(
                    'Total:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '₹${expense.amount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _buildDetailRow(BuildContext context, String label, String value, IconData icon) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

Widget _buildSplitRow(BuildContext context, String memberName, String amount) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(memberName, style: Theme.of(context).textTheme.bodyMedium),
        Text(amount, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        )),
      ],
    ),
  );
}

String _getCategoryDisplayName(String category) {
  switch (category) {
    case 'food':
      return 'Food & Dining';
    case 'transport':
      return 'Transportation';
    case 'entertainment':
      return 'Entertainment';
    case 'utilities':
      return 'Utilities';
    case 'shopping':
      return 'Shopping';
    case 'health':
      return 'Health & Medical';
    case 'education':
      return 'Education';
    case 'other':
      return 'Other';
    default:
      return category;
  }
}

IconData _getCategoryIcon(String category) {
  switch (category) {
    case 'food':
      return Icons.restaurant;
    case 'transport':
      return Icons.directions_car;
    case 'entertainment':
      return Icons.movie;
    case 'utilities':
      return Icons.electric_bolt;
    case 'shopping':
      return Icons.shopping_bag;
    case 'health':
      return Icons.medical_services;
    case 'education':
      return Icons.school;
    case 'other':
      return Icons.more_horiz;
    default:
      return Icons.category;
  }
}

String _formatDetailedDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final expenseDate = DateTime(date.year, date.month, date.day);
  
  if (expenseDate == today) {
    return 'Today';
  } else if (expenseDate == yesterday) {
    return 'Yesterday';
  } else {
    return '${date.day}/${date.month}/${date.year}';
  }
}

String _formatDetailedTime(DateTime date) {
  final hour = date.hour;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  return '$displayHour:$minute $period';
}


