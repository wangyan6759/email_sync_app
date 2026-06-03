import 'package:flutter/material.dart';
import '../models/email_model.dart';
import '../services/email_extractor.dart';

/// 邮件详情页面
class EmailDetailScreen extends StatelessWidget {
  final EmailModel email;

  const EmailDetailScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    final info = EmailExtractorService.extract(email);

    return Scaffold(
      appBar: AppBar(title: const Text('邮件详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 主题
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.subject,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.person, '发件人', email.from),
                  if (email.to.isNotEmpty)
                    _buildInfoRow(Icons.people, '收件人', email.to),
                  _buildInfoRow(Icons.access_time, '日期', email.date),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 提取的信息
          if (info.keyPoints.isNotEmpty || info.actionItems.isNotEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _urgencyBadge(info.urgencyLevel),
                        const SizedBox(width: 8),
                        const Text('关键信息提取',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    if (info.keyPoints.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('📌 关键要点',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(info.keyPoints,
                          style: const TextStyle(fontSize: 13, height: 1.5)),
                    ],
                    if (info.actionItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('✅ 待办事项',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(info.actionItems,
                          style: const TextStyle(fontSize: 13, height: 1.5)),
                    ],
                    if (info.mentionedPeople.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('👤 相关人员',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(info.mentionedPeople,
                          style: const TextStyle(fontSize: 13)),
                    ],
                    if (info.mentionedDates.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('📅 提及日期',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(info.mentionedDates,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),

          // 正文
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('邮件正文',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text(
                    email.body.isEmpty ? '(无内容)' : email.body,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label：', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _urgencyBadge(String level) {
    Color color;
    switch (level) {
      case '高':
        color = Colors.red;
        break;
      case '低':
        color = Colors.green;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '紧急程度：$level',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}