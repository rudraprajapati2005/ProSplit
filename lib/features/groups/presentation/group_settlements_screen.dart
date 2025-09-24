import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../expenses/domain/expense_controller.dart';
import '../../expenses/domain/expense_model.dart';
import '../domain/group_controller.dart';
import '../domain/member_info.dart';

class GroupSettlementsScreen extends ConsumerWidget {
  final String groupId;
  const GroupSettlementsScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(groupExpensesProvider(groupId));
    final currentUser = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settlements'),
      ),
      body: expensesAsync.when(
        data: (expenses) {
          final sorted = [...expenses]..sort((a, b) => a.date.compareTo(b.date));
          return FutureBuilder(
            future: ref.read(groupControllerProvider.notifier).getGroup(groupId),
            builder: (context, snapshot) {
              final group = snapshot.data;
              final memberNames = group?.memberNames ?? const <String, String>{};
              final currentUserId = currentUser?.id ?? '';
              
              // Check if we need to migrate or populate member data
              if (group != null) {
                // First, check if we need to migrate to the new structure
                if (group.members.isEmpty && memberNames.isNotEmpty) {
                  // Migrate to new structure in the background
                  ref.read(groupControllerProvider.notifier).migrateGroupToNewStructure(groupId);
                }
                
                final allMemberIds = <String>{group.createdByUserId};
                allMemberIds.addAll(group.memberUserIds);
                final hasIssues = allMemberIds.any((id) {
                  // Check if we have proper member info in the new structure
                  if (group.members.containsKey(id)) {
                    return false; // We have proper member info
                  }
                  
                  // Fall back to checking legacy memberNames
                  final name = memberNames[id];
                  return name == null || 
                         name.isEmpty || 
                         name == id || // Name is same as user ID
                         name.length > 20; // Likely a Firebase UID
                });
                
                if (hasIssues) {
                  // Populate missing names in the background
                  ref.read(groupControllerProvider.notifier).populateMissingMemberNames(groupId);
                }
              }
              
              final settlements = _computeSettlementsByUserId(sorted, memberNames, currentUserId);

              final youPay = settlements.where((s) => s.from == currentUserId).toList();
              final oweYou = settlements.where((s) => s.to == currentUserId).toList();

              if (settlements.isEmpty) {
                return const Center(child: Text('All settled!'));
              }

              // Calculate totals for summary
              final totalYouPay = youPay.fold(0.0, (sum, s) => sum + s.amount);
              final totalOweYou = oweYou.fold(0.0, (sum, s) => sum + s.amount);
              final netBalance = totalOweYou - totalYouPay;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Settlement Summary Card
                  Card(
                    color: netBalance > 0 ? Colors.green.shade50 : netBalance < 0 ? Colors.red.shade50 : Colors.grey.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settlement Summary',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('You will receive:', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.blue.shade800,
                              )),
                              Text('₹${totalOweYou.toStringAsFixed(2)}', 
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                )),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('You will pay:', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.blue.shade800,
                              )),
                              Text('₹${totalYouPay.toStringAsFixed(2)}', 
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                )),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Net Balance:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              )),
                              Text(
                                '₹${netBalance.abs().toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: netBalance > 0 ? Colors.green : netBalance < 0 ? Colors.red : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          if (netBalance != 0)
                            Text(
                              netBalance > 0 ? 'You are owed money overall' : 'You owe money overall',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: netBalance > 0 ? Colors.green : Colors.red,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Detailed settlements
                  _sectionHeader(context, 'Amount to be paid by you'),
                  if (youPay.isEmpty)
                    _emptyHint(context, 'No payments required')
                  else
                    ...youPay.map((s) => _paymentRow(context, _getDisplayName(s.to, memberNames, currentUserId, members: group?.members), s.amount)),
                  const SizedBox(height: 16),
                  _sectionHeader(context, 'Amount to be received by you'),
                  if (oweYou.isEmpty)
                    _emptyHint(context, 'No pending receipts')
                  else
                    ...oweYou.map((s) => _receiptRow(context, _getDisplayName(s.from, memberNames, currentUserId, members: group?.members), s.amount)),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _SettlementLine {
  final String from; // userId
  final String to;   // userId
  final double amount;
  _SettlementLine(this.from, this.to, this.amount);
}

// Compute balances strictly by userId; map names only for display
List<_SettlementLine> _computeSettlementsByUserId(List<ExpenseModel> expenses, Map<String, String> memberNames, String currentUserId) {
  final Map<String, double> balanceByUserId = {};
  
  // Helper to map the paidBy field to a userId
  // paidBy now contains user IDs directly, but we need to handle legacy data that might contain names
  String _resolvePaidByUserId(String paidBy) {
    // If paidBy is already a user ID (starts with a typical user ID pattern or is in memberNames keys)
    if (memberNames.containsKey(paidBy)) {
      return paidBy;
    }
    
    // Legacy support: if paidBy is a name, try to find the corresponding userId
    final match = memberNames.entries.firstWhere(
      (e) => e.value == paidBy,
      orElse: () => const MapEntry('', ''),
    );
    
    if (match.key.isNotEmpty) {
      return match.key;
    }
    
    // If still no match, return the paidBy as is
    // This handles edge cases where the paidBy field might be corrupted or from legacy data
    return paidBy;
  }

  // Calculate balances for each user
  for (final e in expenses) {
    if (e.isSettled) continue;
    
    // Skip if no participants
    if (e.splitBetween.isEmpty) continue;
    
    // Credit the payer (paidBy is now a userId, but we handle legacy names too)
    final payerId = _resolvePaidByUserId(e.paidBy);
    balanceByUserId[payerId] = (balanceByUserId[payerId] ?? 0) + e.amount;
    
    // Debit each participant
    if (e.customAmounts.isNotEmpty) {
      // Custom amounts - use the specified amounts
      for (final uid in e.splitBetween) {
        final customAmount = e.customAmounts[uid] ?? 0;
        balanceByUserId[uid] = (balanceByUserId[uid] ?? 0) - customAmount;
      }
    } else {
      // Equal split - divide equally
      final perHead = e.amount / e.splitBetween.length;
      for (final uid in e.splitBetween) {
        balanceByUserId[uid] = (balanceByUserId[uid] ?? 0) - perHead;
      }
    }
  }

  // Round to avoid floating point precision issues
  balanceByUserId.updateAll((key, value) => (value * 100).roundToDouble() / 100);
  
  // Remove entries with zero balance (within tolerance)
  balanceByUserId.removeWhere((key, value) => value.abs() < 0.01);

  // Separate creditors and debtors
  final creditors = <MapEntry<String, double>>[];
  final debtors = <MapEntry<String, double>>[];
  
  balanceByUserId.forEach((userId, bal) {
    if (bal > 0.01) {
      creditors.add(MapEntry(userId, bal));
    } else if (bal < -0.01) {
      debtors.add(MapEntry(userId, -bal)); // Store as positive amount owed
    }
  });
  
  // Sort by amount (largest first) for optimal settlement
  creditors.sort((a, b) => b.value.compareTo(a.value));
  debtors.sort((a, b) => b.value.compareTo(a.value));

  // Greedy algorithm to minimize number of transactions
  final result = <_SettlementLine>[];
  int i = 0, j = 0;
  
  while (i < debtors.length && j < creditors.length) {
    final debtor = debtors[i];
    final creditor = creditors[j];
    
    // Calculate the amount to transfer (minimum of what debtor owes and creditor is owed)
    final amount = debtor.value < creditor.value ? debtor.value : creditor.value;
    
    if (amount > 0.01) {
      result.add(_SettlementLine(
        debtor.key, 
        creditor.key, 
        (amount * 100).roundToDouble() / 100
      ));
    }
    
    // Update remaining amounts
    final newDebt = debtor.value - amount;
    final newCredit = creditor.value - amount;
    
    // Move to next debtor if fully settled
    if (newDebt <= 0.01) {
      i++;
    } else {
      debtors[i] = MapEntry(debtor.key, newDebt);
    }
    
    // Move to next creditor if fully settled
    if (newCredit <= 0.01) {
      j++;
    } else {
      creditors[j] = MapEntry(creditor.key, newCredit);
    }
  }
  
  return result;
}

Widget _sectionHeader(BuildContext context, String title) {
  return Text(title, style: Theme.of(context).textTheme.titleMedium);
}

Widget _paymentRow(BuildContext context, String toUser, double amount) {
  return Card(
    child: ListTile(
      leading: const Icon(Icons.arrow_upward, color: Colors.red),
      title: Text('You should pay $toUser'),
      trailing: Text('₹${amount.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          )),
    ),
  );
}

Widget _receiptRow(BuildContext context, String fromUser, double amount) {
  return Card(
    child: ListTile(
      leading: const Icon(Icons.arrow_downward, color: Colors.green),
      title: Text('$fromUser should pay you'),
      trailing: Text('₹${amount.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          )),
    ),
  );
}

Widget _emptyHint(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
  );
}

String _getDisplayName(String userId, Map<String, String> memberNames, String currentUserId, {Map<String, MemberInfo>? members}) {
  // Handle empty or null userId
  if (userId.isEmpty) return 'Unknown User';
  
  // If this is the current user, return "You"
  if (userId == currentUserId) {
    return 'You';
  }
  
  // First try to get the display name from the new members structure
  if (members != null && members.containsKey(userId)) {
    final info = members[userId];
    if (info != null && info.username.isNotEmpty) {
      return info.username;
    }
  }
  
  // Fall back to legacy memberNames map
  final displayName = memberNames[userId];
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  
  // If not found, check if the userId is actually a display name (reverse lookup)
  final reverseMatch = memberNames.entries.firstWhere(
    (entry) => entry.value == userId,
    orElse: () => const MapEntry('', ''),
  );
  
  if (reverseMatch.key.isNotEmpty) {
    return userId; // It's already a display name
  }
  
  // If we still don't have a name, try to extract a readable name from the userId
  // This handles cases where the userId might be an email or have a readable format
  if (userId.contains('@')) {
    // If it's an email, use the part before @
    return userId.split('@')[0];
  }
  
  // If the userId is very long (typical Firebase UID), show a shortened version
  if (userId.length > 20) {
    return 'User ${userId.substring(0, 8)}...';
  }
  
  // Fallback: return the userId as is
  return userId;
}


