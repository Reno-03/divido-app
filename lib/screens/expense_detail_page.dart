import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpenseDetailPage extends StatelessWidget {
  final Map<String, dynamic> expense;
  final Color ownerColor;

  const ExpenseDetailPage({
    super.key,
    required this.expense,
    required this.ownerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.6), // overlay outside Hero
      body: Stack(
        children: [
          // Close by tapping outside
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.transparent),
          ),

          Center(
            child: Hero(
              tag: 'expense_${expense['id']}',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  decoration: BoxDecoration(
                    color: ownerColor.withValues(alpha: 0.15), // match source
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(color: ownerColor, width: 5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // TITLE & TOTAL
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    expense['title'] ?? '',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      decoration: (expense['is_paid'] == true)
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: Colors.white54,
                                    ),
                                  ),
                                  Text(
                                    '${expense['profiles']?['firstname'] ?? ''} ${expense['profiles']?['lastname'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₱ ${expense['total']}',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                decoration: (expense['is_paid'] == true)
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: Colors.white54,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // DESCRIPTION
                        if (expense['description'] != null &&
                            expense['description'].toString().isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              expense['description'],
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ),

                        // PAYERS
                        const Text(
                          'Payers:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        ...((expense['expense_breakdowns'] as List<dynamic>? ??
                                [])
                            .map((b) {
                              final user = b['profiles'];
                              final initials = [
                                user?['firstname']?.substring(0, 1) ?? '',
                                user?['lastname']?.substring(0, 1) ?? '',
                              ].join().toUpperCase();

                              final rawColor = user?['color'] ?? '#6366F1';
                              final userColor = Color(
                                int.parse(
                                  'FF${rawColor.replaceAll('#', '')}',
                                  radix: 16,
                                ),
                              );

                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      // Avatar
                                      UserAvatar(
                                        avatarUrl:
                                            user?['avatar_url'] as String?,
                                        initials: initials,
                                        color: userColor,
                                        size: 32,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${user?['firstname'] ?? ''} ${user?['lastname'] ?? ''}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '₱${b['amount']}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            })
                            .toList()),

                        const SizedBox(height: 16),

                        // CREATED DATE
                        Text(
                          'Created: ${DateFormat.yMMMd().add_jm().format(expense['created_at_local'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // CLOSE BUTTON
                        Center(
                          child: SizedBox(
                            width: double.infinity, // full width
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: ownerColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24, // bigger tap area
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16, // slightly bigger text
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final Color color;
  final double size;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.initials,
    required this.color,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initialsWidget(),
            )
          : _initialsWidget(),
    );
  }

  Widget _initialsWidget() {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
