import 'package:flutter/material.dart';

class Samplepage extends StatefulWidget {
  const Samplepage({super.key});

  @override
  State<Samplepage> createState() => _SamplepageState();
}

class _SamplepageState extends State<Samplepage> {
  final List<Map<String, dynamic>> expenses = [
    {'title': 'Lunch with friends', 'amount': 250, 'type': 'debit'},
    {'title': 'Cab fare', 'amount': 120, 'type': 'credit'},
    {'title' : 'Petrol' , 'amount' : 500, 'type' : 'credit'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ProSplit'),
        backgroundColor: Colors.pink,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Balance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.deepPurple),
                title: const Text('₹1,000'),
                subtitle: const Text('You are owed'),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Recent Expenses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: expenses.length,
                itemBuilder: (context, index) {
                  final expense = expenses[index];
                  return ListTile(
                    leading: Icon(
                      expense['type'] == 'debit' ? Icons.remove_circle : Icons.add_circle,
                      color: expense['type'] == 'debit' ? Colors.red : Colors.green,
                    ),
                    title: Text(expense['title']),
                    trailing: Text(
                      '₹${expense['amount']}',
                      style: TextStyle(
                        color: expense['type'] == 'debit' ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Add expense logic here
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
        backgroundColor: Colors.deepPurple,
      ),
    );
  }
}