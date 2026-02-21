import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';


final user = CurrentUser.instance;
// e.g. "john_doe"

class BalancePage extends StatelessWidget {
  const BalancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Balance',
            style: TextStyle(fontSize: 24),
          ),
          
          Text(user.username ?? 'No user logged in')
        ],
      )
    );
  }
}