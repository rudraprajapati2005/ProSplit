import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/expense_repository.dart';
import '../domain/expense_model.dart';
import 'package:collection/collection.dart';

final expenseControllerProvider = StateNotifierProvider<ExpenseController, AsyncValue<List<ExpenseModel>>>((ref) {
  return ExpenseController(ref.watch(expenseRepositoryProvider));
});

final userExpenseStatsProvider = FutureProvider.family<Map<String, double>, String>((ref, userId) {
  return ref.watch(expenseRepositoryProvider).getUserExpenseStats(userId);
});

// Provider for group expenses
final groupExpensesProvider = StreamProvider.family<List<ExpenseModel>, String>((ref, groupId) {
  return ref.watch(expenseRepositoryProvider).getGroupExpenses(groupId);
});

/// Computes each member's net balance within a group from its expenses.
/// Positive means others owe this member; negative means this member owes others.
final groupBalancesProvider = Provider.family<Map<String, double>, String>((ref, groupId) {
  final expensesAsync = ref.watch(groupExpensesProvider(groupId));
  return expensesAsync.maybeWhen(
    data: (expenses) {
      final Map<String, double> balances = {};
      for (final e in expenses) {
        if (e.isSettled) continue;
        final perHead = e.splitBetween.isEmpty ? 0.0 : e.amount / e.splitBetween.length;
        // credit payer by total amount
        balances[e.paidBy] = (balances[e.paidBy] ?? 0) + e.amount;
        // debit each participant by their share
        for (final participant in e.splitBetween) {
          balances[participant] = (balances[participant] ?? 0) - perHead;
        }
      }
      // Round to 2 decimals to avoid tiny floating residues
      return balances.map((k, v) => MapEntry(k, (v * 100).roundToDouble() / 100));
    },
    orElse: () => <String, double>{},
  );
});

class SettlementEntry {
  final String fromUser; // debtor
  final String toUser;   // creditor
  final double amount;
  SettlementEntry({required this.fromUser, required this.toUser, required this.amount});
}

/// Greedy settlement calculation from net balances to who pays whom.
final groupSettlementsProvider = Provider.family<List<SettlementEntry>, String>((ref, groupId) {
  final balances = ref.watch(groupBalancesProvider(groupId));
  if (balances.isEmpty) return const <SettlementEntry>[];

  final creditors = <MapEntry<String, double>>[];
  final debtors = <MapEntry<String, double>>[];
  for (final entry in balances.entries) {
    if (entry.value > 0.005) creditors.add(MapEntry(entry.key, entry.value));
    else if (entry.value < -0.005) debtors.add(MapEntry(entry.key, -entry.value)); // store positive owed
  }
  // Sort so we consume biggest first
  creditors.sort((a, b) => b.value.compareTo(a.value));
  debtors.sort((a, b) => b.value.compareTo(a.value));

  final settlements = <SettlementEntry>[];
  int i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final debtor = debtors[i];
    final creditor = creditors[j];
    final pay = debtor.value < creditor.value ? debtor.value : creditor.value;
    if (pay > 0.005) {
      settlements.add(SettlementEntry(fromUser: debtor.key, toUser: creditor.key, amount: ((pay * 100).roundToDouble()) / 100));
    }
    final newDeb = debtor.value - pay;
    final newCred = creditor.value - pay;
    if (newDeb <= 0.005) {
      i++;
    } else {
      debtors[i] = MapEntry(debtor.key, newDeb);
    }
    if (newCred <= 0.005) {
      j++;
    } else {
      creditors[j] = MapEntry(creditor.key, newCred);
    }
  }
  return settlements;
});

// Aggregate spend vs share (owes) for a user based on loaded expenses
final userSpendDebtProvider = Provider.family<({double spent, double owes}), String>((ref, userName) {
  final expensesState = ref.watch(expenseControllerProvider);
  return expensesState.maybeWhen(
    data: (expenses) {
      double spent = 0;
      double owes = 0;
      for (final e in expenses) {
        if (e.isSettled) continue;
        final perHead = e.splitBetween.isEmpty ? 0.0 : e.amount / e.splitBetween.length;
        if (e.paidBy == userName) spent += e.amount;
        if (e.splitBetween.isNotEmpty) owes += perHead;
      }
      return (spent: ((spent * 100).roundToDouble()) / 100, owes: ((owes * 100).roundToDouble()) / 100);
    },
    orElse: () => (spent: 0.0, owes: 0.0),
  );
});

// Stream-based totals that don't require imperative loading from widgets
final userSpendDebtStreamProvider = StreamProvider.family<({double spent, double owes}), ({String userId, String userName})>((ref, args) {
  final repo = ref.watch(expenseRepositoryProvider);
  return repo.getUserExpenses(args.userId).map((expenses) {
    double spent = 0;
    double owes = 0;
    for (final e in expenses) {
      if (e.isSettled) continue;
      final perHead = e.splitBetween.isEmpty ? 0.0 : e.amount / e.splitBetween.length;
      if (e.paidBy == args.userName) spent += e.amount;
      if (e.splitBetween.isNotEmpty) owes += perHead;
    }
    return (spent: ((spent * 100).roundToDouble()) / 100, owes: ((owes * 100).roundToDouble()) / 100);
  });
});

class ExpenseController extends StateNotifier<AsyncValue<List<ExpenseModel>>> {
  final ExpenseRepository _expenseRepository;

  ExpenseController(this._expenseRepository) : super(const AsyncValue.loading());

  // Load expenses for a user
  void loadUserExpenses(String userId) {
    state = const AsyncValue.loading();
    _expenseRepository.getUserExpenses(userId).listen(
      (expenses) {
        state = AsyncValue.data(expenses);
      },
      onError: (error, stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );
  }

  // Load expenses for a group
  void loadGroupExpenses(String groupId) {
    state = const AsyncValue.loading();
    _expenseRepository.getGroupExpenses(groupId).listen(
      (expenses) {
        state = AsyncValue.data(expenses);
      },
      onError: (error, stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );
  }

  // Add new expense
  Future<void> addExpense(ExpenseModel expense) async {
    try {
      await _expenseRepository.addExpense(expense);
    } catch (e, st) {
      throw Exception('Failed to add expense: $e');
    }
  }

  // Update expense
  Future<void> updateExpense(ExpenseModel expense) async {
    try {
      await _expenseRepository.updateExpense(expense);
    } catch (e, st) {
      throw Exception('Failed to update expense: $e');
    }
  }

  // Delete expense
  Future<void> deleteExpense(String expenseId) async {
    try {
      await _expenseRepository.deleteExpense(expenseId);
    } catch (e, st) {
      throw Exception('Failed to delete expense: $e');
    }
  }

  // Mark expense as settled
  Future<void> markExpenseAsSettled(String expenseId) async {
    try {
      await _expenseRepository.markExpenseAsSettled(expenseId);
    } catch (e, st) {
      throw Exception('Failed to mark expense as settled: $e');
    }
  }
}

