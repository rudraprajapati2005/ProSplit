import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../expenses/domain/expense_controller.dart';
import '../../expenses/domain/expense_model.dart';
import '../../expenses/presentation/add_expense_screen.dart';
import '../domain/group_controller.dart';

class GroupExpensesScreen extends ConsumerWidget {
  final String groupId;
  const GroupExpensesScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(groupExpensesProvider(groupId));
    final currentUser = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Expenses')),
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

              // Compute settlements keyed by display names
              final settlements = _computeSettlements(groupExpenses, memberNames);

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: groupExpenses.length + (settlements.isNotEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  // Inject settlement summary card at the top
                  if (settlements.isNotEmpty && index == 0) {
                    return _settlementCard(context, settlements);
                  }
                  final expIndex = settlements.isNotEmpty ? index - 1 : index;
                  final expense = groupExpenses[expIndex];
                  final isMine = expense.paidBy == (currentUser?.name ?? '');
                  final dateLabel = _formatDayLabel(expense.date);
                  final bool showHeader = expIndex == 0 ||
                      _formatDayLabel(groupExpenses[expIndex - 1].date) != dateLabel;

                  final bubble = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isMine) _avatar(expense.paidBy),
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
                                        expense.amount.toStringAsFixed(2),
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Paid by ${expense.paidBy == (currentUser?.name ?? '') ? 'You' : expense.paidBy}', style: Theme.of(context).textTheme.bodySmall),
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
                      if (isMine) _avatar(expense.paidBy),
                    ],
                  );

                  if (showHeader) {
                    return Column(
                      children: [
                        const SizedBox(height: 6),
                        _dateHeader(context, dateLabel),
                        bubble,
                      ],
                    );
                  }
                  return bubble;
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

class _SettlementLine {
  final String from;
  final String to;
  final double amount;
  _SettlementLine(this.from, this.to, this.amount);
}

// Compute settlements locally based on current expense list and member name mapping.
List<_SettlementLine> _computeSettlements(List<ExpenseModel> expenses, Map<String, String> memberNames) {
  // Build balances keyed by display name for UI simplicity.
  final Map<String, double> balanceByName = {};
  for (final e in expenses) {
    if (e.isSettled) continue;
    final perHead = e.splitBetween.isEmpty ? 0.0 : e.amount / e.splitBetween.length;
    // credit payer (paidBy is a name string already)
    balanceByName[e.paidBy] = (balanceByName[e.paidBy] ?? 0) + e.amount;
    // for each participant, we only have userIds; try to map to display names, else use id
    for (final uid in e.splitBetween) {
      final name = memberNames[uid] ?? uid;
      balanceByName[name] = (balanceByName[name] ?? 0) - perHead;
    }
  }

  final creditors = <MapEntry<String, double>>[];
  final debtors = <MapEntry<String, double>>[];
  balanceByName.forEach((name, bal) {
    if (bal > 0.005) creditors.add(MapEntry(name, bal));
    else if (bal < -0.005) debtors.add(MapEntry(name, -bal));
  });
  creditors.sort((a, b) => b.value.compareTo(a.value));
  debtors.sort((a, b) => b.value.compareTo(a.value));

  final result = <_SettlementLine>[];
  int i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final d = debtors[i];
    final c = creditors[j];
    final amt = d.value < c.value ? d.value : c.value;
    if (amt > 0.005) {
      result.add(_SettlementLine(d.key, c.key, ((amt * 100).roundToDouble()) / 100));
    }
    final newD = d.value - amt;
    final newC = c.value - amt;
    if (newD <= 0.005) {
      i++;
    } else {
      debtors[i] = MapEntry(d.key, newD);
    }
    if (newC <= 0.005) {
      j++;
    } else {
      creditors[j] = MapEntry(c.key, newC);
    }
  }
  return result;
}

Widget _settlementCard(BuildContext context, List<_SettlementLine> settlements) {
  if (settlements.isEmpty) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.balance, color: Colors.green),
            const SizedBox(width: 8),
            Text('All settled', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Settlements', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in settlements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.from} pays ${s.to}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    s.amount.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}


