import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/expense_model.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(FirebaseFirestore.instance);
});

class ExpenseRepository {
  final FirebaseFirestore _firestore;

  ExpenseRepository(this._firestore);

  // Get all expenses for a user
  Stream<List<ExpenseModel>> getUserExpenses(String userId) {
    // Avoid requiring a composite index by removing server-side orderBy
    // and sorting locally by date desc.
    return _firestore
        .collection('expenses')
        .where('splitBetween', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => ExpenseModel.fromJson(doc.data()))
              .toList();
          list.sort((a, b) => b.date.compareTo(a.date));
          return list;
        });
  }

  // Get expenses for a specific group
  Stream<List<ExpenseModel>> getGroupExpenses(String groupId) {
    // Avoid requiring a composite index by removing server-side orderBy
    // and sorting locally by date desc.
    return _firestore
        .collection('expenses')
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => ExpenseModel.fromJson(doc.data()))
              .toList();
          list.sort((a, b) => b.date.compareTo(a.date));
          return list;
        });
  }

  // Add new expense
  Future<void> addExpense(ExpenseModel expense) async {
    try {
      // Add a timeout so UI won't spin forever on stalled networks
      await _firestore
          .collection('expenses')
          .doc(expense.id)
          .set(expense.toJson())
          .timeout(const Duration(seconds: 15));
    } on FirebaseException catch (e) {
      // Surface Firestore-specific errors (e.g., permission-denied)
      throw Exception('Firestore error (${e.code}): ${e.message}');
    } on TimeoutException {
      throw Exception('Timeout: taking too long to save. Check connection.');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  // Update expense
  Future<void> updateExpense(ExpenseModel expense) async {
    await _firestore
        .collection('expenses')
        .doc(expense.id)
        .update(expense.toJson());
  }

  // Delete expense
  Future<void> deleteExpense(String expenseId) async {
    await _firestore.collection('expenses').doc(expenseId).delete();
  }

  // Mark expense as settled
  Future<void> markExpenseAsSettled(String expenseId) async {
    await _firestore
        .collection('expenses')
        .doc(expenseId)
        .update({'isSettled': true});
  }

  // Get expense statistics for a user
  Future<Map<String, double>> getUserExpenseStats(String userId) async {
    final snapshot = await _firestore
        .collection('expenses')
        .where('splitBetween', arrayContains: userId)
        .get();

    final expenses = snapshot.docs
        .map((doc) => ExpenseModel.fromJson(doc.data()))
        .toList();

    final stats = <String, double>{};
    for (final expense in expenses) {
      final category = expense.category;
      final amount = expense.amount / expense.splitBetween.length;
      stats[category] = (stats[category] ?? 0) + amount;
    }

    return stats;
  }

  // Update all expenses where a user is the payer (when user changes name)
  Future<void> updateExpensesPaidBy(String oldName, String newName) async {
    final snapshot = await _firestore
        .collection('expenses')
        .where('paidBy', isEqualTo: oldName)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'paidBy': newName});
    }
    
    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }
}

