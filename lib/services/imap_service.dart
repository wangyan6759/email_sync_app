import 'dart:io';
import 'dart:convert';
import 'dart:math';
import '../models/email_model.dart';

/// IMAP 邮件同步服务 - 通过原生 Socket 连接 IMAP 服务器
class ImapService {
  Socket? _socket;
  String _buffer = '';
  bool _loggedIn = false;
  int _tagCounter = 0;
  String? _lastError;

  String? get lastError => _lastError;

  /// 连接到 IMAP 服务器（根据配置自动选择 SSL 或普通连接）
  Future<bool> connect(ImapConfig config) async {
    try {
      _lastError = null;
      
      if (config.useSSL) {
        return await _connectSecure(config);
      } else {
        return await _connectPlain(config);
      }
    } catch (e, stackTrace) {
      _lastError = '连接失败: $e\n$stackTrace';
      print(_lastError);
      return false;
    }
  }

  /// 普通连接（无 SSL）
  Future<bool> _connectPlain(ImapConfig config) async {
    try {
      print('正在连接 ${config.server}:${config.port} (无 SSL)...');
      _socket = await Socket.connect(
        config.server,
        config.port,
        timeout: const Duration(seconds: 30),
      );
      print('Socket 连接成功');
      
      _setupSocketListeners();
      
      // 等待欢迎信息
      final welcome = await _readResponse(timeout: 10);
      print('服务器响应: $welcome');
      
      // 登录
      return await _login(config.username, config.password);
    } catch (e, stackTrace) {
      _lastError = '普通连接失败: $e\n$stackTrace';
      print(_lastError);
      return false;
    }
  }

  /// SSL 安全连接
  Future<bool> _connectSecure(ImapConfig config) async {
    try {
      print('正在连接 ${config.server}:${config.port} (SSL)...');
      
      // 尝试使用安全套接字连接
      _socket = await SecureSocket.connect(
        config.server,
        config.port,
        timeout: const Duration(seconds: 30),
        onBadCertificate: (cert) {
          // 忽略证书验证错误（自签名证书等）
          print('忽略证书验证');
          return true;
        },
      );
      print('SSL 连接成功');
      
      _setupSocketListeners();
      
      // 等待欢迎信息
      final welcome = await _readResponse(timeout: 10);
      print('服务器响应: $welcome');
      
      // 登录
      return await _login(config.username, config.password);
    } catch (e, stackTrace) {
      _lastError = 'SSL 连接失败: $e\n$stackTrace';
      print(_lastError);
      return false;
    }
  }

  /// 设置 Socket 监听器
  void _setupSocketListeners() {
    _socket!.listen(
      (data) {
        try {
          final decoded = utf8.decode(data);
          _buffer += decoded;
          // print('收到数据: $decoded');
        } catch (e) {
          print('解码数据失败: $e');
        }
      },
      onError: (error) {
        _lastError = 'Socket 错误: $error';
        print(_lastError);
      },
      onDone: () {
        print('Socket 连接关闭');
      },
    );
  }

  /// 生成 IMAP 标签
  String _tag() {
    _tagCounter++;
    return 'A$_tagCounter';
  }

  /// 发送 IMAP 命令
  Future<void> _sendCommand(String command) async {
    try {
      final data = '$command\r\n';
      print('发送命令: $command');
      _socket!.add(utf8.encode(data));
      await _socket!.flush();
    } catch (e) {
      throw Exception('发送命令失败: $e');
    }
  }

  /// 读取响应（不等待特定标签）
  Future<String> _readResponse({int timeout = 10}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inSeconds < timeout) {
      if (_buffer.contains('\r\n')) {
        final lines = _buffer.split('\r\n');
        // 保留最后不完整的行
        if (_buffer.endsWith('\r\n')) {
          _buffer = '';
        } else {
          _buffer = lines.removeLast();
        }
        return lines.join('\n');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('读取响应超时（$timeout秒）');
  }

  /// 读取多行响应直到指定标签
  Future<String> _readUntilTag(String tag, {int timeout = 30}) async {
    final start = DateTime.now();
    final allLines = <String>[];

    while (DateTime.now().difference(start).inSeconds < timeout) {
      if (_buffer.contains('\r\n')) {
        final lines = _buffer.split('\r\n');
        if (_buffer.endsWith('\r\n')) {
          _buffer = '';
        } else {
          _buffer = lines.removeLast();
        }

        for (final line in lines) {
          allLines.add(line);
          if (line.startsWith('$tag ')) {
            return allLines.join('\n');
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException('读取响应超时 (tag: $tag)');
  }

  /// 登录
  Future<bool> _login(String username, String password) async {
    try {
      final tag = _tag();
      await _sendCommand('$tag LOGIN "$username" "$password"');
      
      final response = await _readUntilTag(tag, timeout: 20);
      print('登录响应: $response');
      
      if (response.contains('$tag OK')) {
        _loggedIn = true;
        print('登录成功！');
        return true;
      } else {
        _lastError = '登录失败: $response';
        print(_lastError);
        return false;
      }
    } catch (e, stackTrace) {
      _lastError = '登录异常: $e\n$stackTrace';
      print(_lastError);
      return false;
    }
  }

  /// 搜索邮件
  Future<List<EmailModel>> searchEmails(
    List<String> keywords, {
    int searchDays = 30,
    String mailbox = 'INBOX',
  }) async {
    if (!_loggedIn || _socket == null) {
      _lastError = '未连接到服务器';
      throw Exception('未连接到服务器');
    }

    final emails = <EmailModel>[];

    try {
      // 选择邮箱
      var tag = _tag();
      await _sendCommand('$tag SELECT "$mailbox"');
      await _readUntilTag(tag, timeout: 20);
      print('已选择邮箱: $mailbox');

      // 计算日期
      final sinceDate = _formatSearchDate(searchDays);

      // 第一步：搜索所有邮件
      tag = _tag();
      await _sendCommand('$tag SEARCH SINCE $sinceDate');
      final searchResponse = await _readUntilTag(tag, timeout: 30);
      
      // 解析邮件 ID
      final allIds = <String>[];
      for (final line in searchResponse.split('\n')) {
        if (line.startsWith('* SEARCH')) {
          final parts = line.split(' ');
          for (int i = 2; i < parts.length; i++) {
            final id = parts[i].trim();
            if (id.isNotEmpty && int.tryParse(id) != null) {
              allIds.add(id);
            }
          }
        }
      }

      if (allIds.isEmpty) {
        print('没有找到邮件');
        return emails;
      }

      print('找到 ${allIds.length} 封邮件');

      // 第二步：批量获取邮件头
      final matchedIds = <String>[];
      final batchSize = 30;

      for (int i = 0; i < allIds.length; i += batchSize) {
        final batch = allIds.sublist(i, min(i + batchSize, allIds.length));
        tag = _tag();
        
        final idsStr = batch.join(',');
        await _sendCommand(
          '$tag FETCH $idsStr (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])',
        );

        try {
          final response = await _readUntilTag(tag, timeout: 60);
          final fetchResults = _parseFetchResponse(response);
          for (final result in fetchResults) {
            final subject = result['subject'] ?? '';
            if (_matchesKeywords(subject, keywords)) {
              matchedIds.add(result['id']!);
            }
          }
        } catch (e) {
          print('批量获取失败: $e');
        }
      }

      print('标题匹配邮件: ${matchedIds.length} 封');

      // 第三步：下载匹配邮件的完整内容
      for (final id in matchedIds) {
        try {
          tag = _tag();
          await _sendCommand('$tag FETCH $id (BODY[])');
          final response = await _readUntilTag(tag, timeout: 120);

          final email = _parseFullEmail(response, id);
          if (email != null) {
            if (!_isReplyOrForward(email.subject)) {
              emails.add(email);
            }
          }
        } catch (e) {
          print('下载邮件 $id 失败: $e');
        }
      }

      print('最终匹配有效邮件: ${emails.length} 封');
    } catch (e, stackTrace) {
      _lastError = '搜索邮件出错: $e\n$stackTrace';
      print(_lastError);
      rethrow;
    }

    return emails;
  }

  /// 格式化搜索日期 (DD-Mon-YYYY)
  String _formatSearchDate(int daysAgo) {
    final date = DateTime.now().subtract(Duration(days: daysAgo));
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day}-${months[date.month - 1]}-${date.year}';
  }

  /// 解析 FETCH 响应
  List<Map<String, String>> _parseFetchResponse(String response) {
    final results = <Map<String, String>>[];
    final lines = response.split('\n');

    String? currentId;
    String? subject;
    String? from;
    String? date;

    for (final line in lines) {
      final fetchMatch = RegExp(r'^\* (\d+) FETCH').firstMatch(line);
      if (fetchMatch != null) {
        if (currentId != null) {
          results.add({
            'id': currentId,
            'subject': _decodeMimeHeader(subject ?? ''),
            'from': from ?? '',
            'date': date ?? '',
          });
        }
        currentId = fetchMatch.group(1);
        subject = null;
        from = null;
        date = null;
      }

      if (line.contains('SUBJECT')) {
        final match = RegExp(r'SUBJECT\s+"?([^"]*)"?', caseSensitive: false)
            .firstMatch(line);
        if (match != null) {
          subject = match.group(1)?.trim() ?? '';
        } else {
          final idx = line.indexOf('SUBJECT', 0);
          if (idx >= 0) {
            subject = line.substring(idx + 7).trim();
          }
        }
      }
      if (line.contains('FROM')) {
        final match = RegExp(r'FROM\s+"?([^"]*)"?', caseSensitive: false)
            .firstMatch(line);
        if (match != null) {
          from = match.group(1)?.trim() ?? '';
        }
      }
      if (line.contains('DATE')) {
        final match = RegExp(r'DATE\s+"?([^"]*)"?', caseSensitive: false)
            .firstMatch(line);
        if (match != null) {
          date = match.group(1)?.trim() ?? '';
        }
      }
    }

    if (currentId != null) {
      results.add({
        'id': currentId,
        'subject': _decodeMimeHeader(subject ?? ''),
        'from': from ?? '',
        'date': date ?? '',
      });
    }

    final seen = <String>{};
    results.removeWhere((r) => !seen.add(r['id']!));
    return results;
  }

  /// 解析完整邮件
  EmailModel? _parseFullEmail(String response, String id) {
    try {
      String? subject, from, to, cc, date;
      final bodyBuffer = StringBuffer();

      final lines = response.split('\n');
      bool inHeader = true;
      bool inBody = false;
      
      // 找到 BODY[] 的内容开始位置
      int bodyStartIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('BODY[]') && lines[i].contains('{')) {
          bodyStartIdx = i + 1;
          break;
        }
      }

      if (bodyStartIdx < 0) {
        // 简单解析模式
        for (final line in lines) {
          if (inHeader && line.trim().isEmpty) {
            inHeader = false;
            inBody = true;
            continue;
          }

          if (inHeader) {
            final lower = line.toLowerCase();
            if (lower.startsWith('subject:')) {
              subject = _decodeMimeHeader(line.substring(8).trim());
            } else if (lower.startsWith('from:')) {
              from = _decodeMimeHeader(line.substring(5).trim());
            } else if (lower.startsWith('to:')) {
              to = _decodeMimeHeader(line.substring(3).trim());
            } else if (lower.startsWith('cc:')) {
              cc = _decodeMimeHeader(line.substring(3).trim());
            } else if (lower.startsWith('date:')) {
              date = line.substring(5).trim();
            }
          } else if (inBody) {
            bodyBuffer.writeln(line);
          }
        }
      } else {
        // 带 BODY[] 的解析
        for (final line in lines) {
          final lower = line.toLowerCase();
          if (lower.startsWith('subject:')) {
            subject = _decodeMimeHeader(line.substring(8).trim());
          } else if (lower.startsWith('from:')) {
            from = _decodeMimeHeader(line.substring(5).trim());
          } else if (lower.startsWith('to:')) {
            to = _decodeMimeHeader(line.substring(3).trim());
          } else if (lower.startsWith('cc:')) {
            cc = _decodeMimeHeader(line.substring(3).trim());
          } else if (lower.startsWith('date:')) {
            date = line.substring(5).trim();
          }
        }
        
        // 提取正文
        for (int i = bodyStartIdx; i < lines.length; i++) {
          if (lines[i].trim() == ')' || lines[i].startsWith('A') && lines[i].contains('OK')) {
            break;
          }
          bodyBuffer.writeln(lines[i]);
        }
      }

      var body = bodyBuffer.toString().trim();
      body = _cleanBody(body);

      return EmailModel(
        subject: subject ?? '(无主题)',
        from: from ?? '未知',
        to: to ?? '',
        cc: cc ?? '',
        date: date ?? '',
        body: body,
      );
    } catch (e) {
      print('解析邮件 $id 失败: $e');
      return null;
    }
  }

  /// 解码 MIME 编码的标题
  String _decodeMimeHeader(String header) {
    if (header.isEmpty) return header;

    final regex = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=');
    return header.replaceAllMapped(regex, (match) {
      final charset = match.group(1) ?? 'utf-8';
      final encoding = match.group(2)?.toUpperCase() ?? 'B';
      final encoded = match.group(3) ?? '';

      try {
        if (encoding == 'B') {
          return utf8.decode(base64.decode(encoded));
        } else {
          final decoded = encoded
              .replaceAll('_', ' ')
              .replaceAllMapped(RegExp(r'=([0-9A-F]{2})'), (m) {
            return String.fromCharCode(
              int.parse(m.group(1)!, radix: 16),
            );
          });
          return utf8.decode(decoded.runes.toList());
        }
      } catch (_) {
        return encoded;
      }
    });
  }

  /// 检查主题是否匹配关键词
  bool _matchesKeywords(String subject, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final lowerSubject = subject.toLowerCase();
    for (final keyword in keywords) {
      if (keyword.isNotEmpty && lowerSubject.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// 判断是否为回复/转发邮件
  bool _isReplyOrForward(String subject) {
    final patterns = [
      RegExp(r'^Re\s*:', caseSensitive: false),
      RegExp(r'^回复\s*:', caseSensitive: false),
      RegExp(r'^Fwd\s*:', caseSensitive: false),
      RegExp(r'^转发\s*:', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      if (pattern.hasMatch(subject)) return true;
    }
    return false;
  }

  /// 清理邮件正文
  String _cleanBody(String body) {
    body = body.replaceAll(RegExp(r'--=_\w+'), '');
    body = body.replaceAll(RegExp(r'^Content-.*$', multiLine: true), '');
    body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return body.trim();
  }

  /// 断开连接
  void disconnect() {
    try {
      if (_loggedIn && _socket != null) {
        final tag = _tag();
        _sendCommand('$tag LOGOUT');
      }
    } catch (_) {}
    try {
      _socket?.destroy();
    } catch (_) {}
    _loggedIn = false;
    _buffer = '';
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
