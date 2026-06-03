import 'package:flutter/material.dart';
import '../models/email_model.dart';
import 'email_detail_screen.dart';

/// 邮件列表页面
class EmailListScreen extends StatelessWidget {
  final List<EmailModel> emails;
  final int totalCount;

  const EmailListScreen({
    super.key,
    required this.emails,
    this.totalCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (emails.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '暂无邮件数据',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              totalCount > 0 ? '标题匹配 $totalCount 封邮件' : '请先同步邮件',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (totalCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.email, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  '共 $totalCount 封邮件',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: emails.length,
            itemBuilder: (context, index) {
              final email = emails[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EmailDetailScreen(email: email),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email.subject,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                email.from,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(
                              email.date.length > 17
                                  ? email.date.substring(0, 17)
                                  : email.date,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}