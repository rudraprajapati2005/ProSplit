import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/expense_repository.dart';
import '../domain/expense_model.dart';

final expenseControllerProvider = StateNotifierProvider<ExpenseController, AsyncValue<List<ExpenseModel>>>((ref) {
  return ExpenseController(ref.watch(expenseRepositoryProvider));
});

final userExpenseStatsProvider = FutureProvider.family<Map<String, double>, String>((ref, userId) {
  return ref.watch(expenseRepositoryProvider).getUserExpenseStats(userId);
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

