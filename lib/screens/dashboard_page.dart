import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:divido_app/providers/expense_provider.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  String _getFunGreeting(String name) {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Rise and shine, $name!';
    } else if (hour < 17) {
      return 'Check your balance, $name!';
    } else {
      return 'Chill time, $name!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = CurrentUser.instance.username ?? 'there';
    final currentUserId = CurrentUser.instance.id;
    final funGreeting = _getFunGreeting(firstName);

    final expenseProvider = Provider.of<ExpenseProvider>(context);

    double totalGroupExpense = 0;
    double totalOwnExpense = 0;

    for (final expense in expenseProvider.expenses) {
      totalGroupExpense += (expense['total'] as num?)?.toDouble() ?? 0.0;

      final breakdowns = expense['expense_breakdowns'] as List<dynamic>? ?? [];
      for (final b in breakdowns) {
        if (b['payer_id'] == currentUserId) {
          totalOwnExpense += (b['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              Text(
                funGreeting,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),

              const SizedBox(height: 20),

              Center(
                child: Image.asset(
                  'assets/divido-logo-animating.gif',
                  width: 200,
                ),
              ),

              const SizedBox(height: 30),

              Row(
                children: [
                  Expanded(
                    child: _buildCardTile(
                      'Total group expense',
                      Icons.group_outlined,
                      '₱ ${totalGroupExpense.toStringAsFixed(2)}',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCardTile(
                      'Total own expense',
                      Icons.person_outline,
                      '₱ ${totalOwnExpense.toStringAsFixed(2)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardTile(String title, IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3C3C63),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            offset: const Offset(0, 8),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFF3C3C63),
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
