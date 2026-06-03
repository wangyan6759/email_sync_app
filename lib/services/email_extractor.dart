import 'dart:convert';
import '../models/email_model.dart';

/// 邮件信息提取器 - 从邮件中提取结构化关键信息
class EmailExtractorService {
  /// 从一封邮件中提取结构化信息
  static ExtractedInfo extract(EmailModel email) {
    final body = email.body;
    final subject = email.subject;

    return ExtractedInfo(
      subject: subject,
      from: email.from,
      date: email.date,
      summary: _generateSummary(body, subject),
      keyPoints: _extractKeyPoints(body),
      actionItems: _extractActionItems(body),
      mentionedPeople: _extractPeople(body),
      mentionedDates: _extractDates(body),
      urgencyLevel: _detectUrgency(subject, body),
    );
  }

  /// 批量提取
  static List<ExtractedInfo> extractAll(List<EmailModel> emails) {
    return emails.map((e) => extract(e)).toList();
  }

  /// 生成摘要
  static String _generateSummary(String body, String subject) {
    if (body.isEmpty) return subject;
    final clean = body.replaceAll(RegExp(r'\s+'), ' ');
    return clean.length > 200 ? '${clean.substring(0, 200)}...' : clean;
  }

  /// 提取关键要点
  static String _extractKeyPoints(String body) {
    if (body.isEmpty) return '';

    final points = <String>[];

    // 查找带标记的要点
    final patterns = [
      RegExp(r'(?:要点|重点|关键|核心|主要内容|主要包括)[：:]\s*(.+?)(?:\n|$)'),
      RegExp(r'[1-9][.、]\s*(.+?)(?:\n|$)'),
      RegExp(r'(?:注意|提醒|请关注|重要)[：:]\s*(.+?)(?:\n|$)'),
      RegExp(r'(?:●|◆|▪|-\s)\s*(.+?)(?:\n|$)'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(body);
      for (final m in matches) {
        final text = m.group(1)?.trim() ?? '';
        if (text.length > 10) {
          points.add(text);
        }
      }
    }

    // 如果没找到标记要点，提取含关键词的句子
    if (points.isEmpty) {
      const keywords = ['重要', '关键', '注意', '必须', '需要', '建议', '要求', '截止'];
      for (final line in body.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.length > 15 &&
            keywords.any((kw) => trimmed.contains(kw))) {
          points.add(trimmed);
        }
      }
    }

    return points.take(10).join('\n');
  }

  /// 提取待办事项
  static String _extractActionItems(String body) {
    if (body.isEmpty) return '';

    final items = <String>[];

    // 查找待办标记
    final patterns = [
      RegExp(
        r'(?:待办|行动项|TODO|to.?do|action\s*item|下一步|后续)[：:]\s*(.+?)(?:\n|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:请|需).{0,10}(?:完成|处理|回复|确认|审核|提交|跟进)(?:.{0,30})(?:\n|$)',
      ),
      RegExp(r'(?:负责|由).{0,5}\w+.{0,20}(?:完成|处理)(?:.{0,30})(?:\n|$)'),
      RegExp(r'deadline\s*[:：]\s*.+?(?:\n|$)', caseSensitive: false),
      RegExp(r'截止日期\s*[:：]\s*.+?(?:\n|$)'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(body);
      for (final m in matches) {
        final text = m.group(0)?.trim() ?? '';
        if (text.length > 5) {
          items.add(text);
        }
      }
    }

    return items.take(10).join('\n');
  }

  /// 提取提及的人员
  static String _extractPeople(String body) {
    if (body.isEmpty) return '';

    final people = <String>{};

    final patterns = [
      RegExp(r'(?:联系人|负责人|项目经理|产品经理)[：:]\s*(\w{2,6})'),
      RegExp(r'(@\w+)'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(body);
      for (final m in matches) {
        final name = m.group(1)?.trim() ?? '';
        if (name.length >= 2 && name.length <= 20) {
          people.add(name);
        }
      }
    }

    return people.isEmpty ? '' : people.join('、');
  }

  /// 提取提及的日期
  static String _extractDates(String body) {
    if (body.isEmpty) return '';

    final dates = <String>[];

    final patterns = [
      RegExp(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}'),
      RegExp(r'\d{1,2}[-/]\d{1,2}[-/]\d{4}'),
      RegExp(r'\d{4}年\d{1,2}月\d{1,2}日'),
      RegExp(r'\d{1,2}月\d{1,2}日'),
      RegExp(r'(?:今天|明天|后天|下周|下月|下周一|下周二|下周三|下周四|下周五)'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(body);
      for (final m in matches) {
        dates.add(m.group(0)!);
      }
    }

    return dates.isEmpty ? '' : dates.take(5).join('、');
  }

  /// 检测紧急程度
  static String _detectUrgency(String subject, String body) {
    final text = '$subject $body'.toLowerCase();

    const urgentKeywords = [
      '紧急', '急', 'urgent', 'immediately', 'asap', 'critical',
    ];
    const lowKeywords = [
      '请查收', 'fyi', '仅供参考', '通知', 'notice',
    ];

    if (urgentKeywords.any((kw) => text.contains(kw))) return '高';
    if (lowKeywords.any((kw) => text.contains(kw))) return '低';
    return '中';
  }
}