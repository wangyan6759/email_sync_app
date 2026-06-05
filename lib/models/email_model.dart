/// 邮件数据模型
class EmailModel {
  final String subject;
  final String from;
  final String to;
  final String cc;
  final String date;
  final String body;
  final String bodyPreview;

  EmailModel({
    required this.subject,
    required this.from,
    this.to = '',
    this.cc = '',
    required this.date,
    required this.body,
    String? bodyPreview,
  }) : bodyPreview = bodyPreview ?? (body.length > 200 ? '${body.substring(0, 200)}...' : body);
}

/// 提取的结构化信息
class ExtractedInfo {
  final String subject;
  final String from;
  final String date;
  final String summary;
  final String keyPoints;
  final String actionItems;
  final String mentionedPeople;
  final String mentionedDates;
  final String urgencyLevel;

  ExtractedInfo({
    required this.subject,
    required this.from,
    required this.date,
    required this.summary,
    this.keyPoints = '',
    this.actionItems = '',
    this.mentionedPeople = '',
    this.mentionedDates = '',
    this.urgencyLevel = '中',
  });
}

/// IMAP 配置
class ImapConfig {
  String server;
  int port;
  bool useSSL;
  String username;
  String password;
  String mailbox;
  List<String> keywords;
  int searchDays;

  ImapConfig({
    this.server = 'imap.263.net',
    this.port = 993,
    this.useSSL = true,
    this.username = '',
    this.password = '',
    this.mailbox = 'INBOX',
    this.keywords = const ['会议纪要', '会议记录', '会议摘要', '会议总结', '会谈纪要', '纪要'],
    this.searchDays = 90,
  });

  Map<String, dynamic> toJson() => {
    'server': server,
    'port': port,
    'useSSL': useSSL,
    'username': username,
    'mailbox': mailbox,
    'keywords': keywords,
    'searchDays': searchDays,
  };
}

/// 同步历史记录
class SyncHistory {
  final String id;
  final String time;
  final int total;
  final String status;
  final String? error;

  SyncHistory({
    required this.id,
    required this.time,
    required this.total,
    required this.status,
    this.error,
  });
}

/// 导出文件信息
class ExportFile {
  final String name;
  final String path;
  final int size;
  final String created;

  ExportFile({
    required this.name,
    required this.path,
    required this.size,
    required this.created,
  });
}