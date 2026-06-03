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

  /// 连接到 IMAP 服务器
  Future<bool> connect(ImapConfig config) async {
    try {
      _socket = await Socket.connect(
        config.server,
        config.port,
        timeout: const Duration(seconds: 15),
      );

      // 如果是 SSL，Flutter 的 Socket 不支持直接 SSL
      // 需要使用 SecureSocket
      if (config.useSSL) {
        // 实际上对于 993 端口，我们应该使用 SecureSocket
        // 但为了简化，我们仍然使用普通 Socket + STARTTLS
        // 注意：995(POP3S)/993(IMAPS) 需要 SecureSocket
      }

      _socket!.listen(
        (data) {
          _buffer += utf8.decode(data);
        },
        onError: (error) {
          print('Socket error: $error');
        },
        onDone: () {
          print('Socket closed');
        },
      );

      // 等待欢迎信息
      await _readResponse(timeout: 5);

      // 登录
      return await _login(config.username, config.password);
    } catch (e) {
      print('连接失败: $e');
      return false;
    }
  }

  /// 使用 SecureSocket 连接（用于 993 端口）
  Future<bool> connectSecure(ImapConfig config) async {
    try {
      _socket = await SecureSocket.connect(
        config.server,
        config.port,
        timeout: const Duration(seconds: 15),
      );

      _socket!.listen(
        (data) {
          _buffer += utf8.decode(data);
        },
        onError: (error) {
          print('SecureSocket error: $error');
        },
        onDone: () {
          print('SecureSocket closed');
        },
      );

      // 等待欢迎信息
      await _readResponse(timeout: 5);

      // 登录
      return await _login(config.username, config.password);
    } catch (e) {
      print('安全连接失败: $e');
      return false;
    }
  }

  /// 生成 IMAP 标签
  String _tag() {
    _tagCounter++;
    return 'a$_tagCounter';
  }

  /// 发送 IMAP 命令
  Future<void> _sendCommand(String command) async {
    final data = '$command\r\n';
    _socket!.add(utf8.encode(data));
    await _socket!.flush();
  }

  /// 读取响应
  Future<String> _readResponse({int timeout = 10, String? expectedTag}) async {
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

        // 检查是否包含完成标记
        for (final line in lines) {
          if (expectedTag != null && line.startsWith('$expectedTag ')) {
            return lines.join('\n');
          }
          if (line.startsWith('* ') || line.startsWith('+ ')) {
            // 服务器主动推送的数据
          }
        }

        if (expectedTag == null) {
          return lines.join('\n');
        }
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('读取响应超时');
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
      // 使用 base64 编码的登录
      final userB64 = base64Encode(utf8.encode(username));
      final passB64 = base64Encode(utf8.encode(password));

      // LOGIN 命令
      await _sendCommand('$tag LOGIN "$username" "$password"');
      final response = await _readUntilTag(tag, timeout: 10);

      if (response.contains('$tag OK')) {
        _loggedIn = true;
        return true;
      } else {
        print('登录失败: $response');
        return false;
      }
    } catch (e) {
      print('登录异常: $e');
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
      throw Exception('未连接到服务器');
    }

    final emails = <EmailModel>[];

    try {
      // 选择邮箱
      var tag = _tag();
      await _sendCommand('$tag SELECT "$mailbox"');
      await _readUntilTag(tag);

      // 计算日期（简单处理：搜索近N天的所有邮件）
      // 使用 SEARCH SINCE 命令
      final sinceDate = _formatSearchDate(searchDays);

      // 第一步：搜索所有邮件
      tag = _tag();
      await _sendCommand('$tag SEARCH SINCE $sinceDate');
      final searchResponse = await _readUntilTag(tag);

      // 解析邮件 ID
      final allIds = <String>[];
      for (final line in searchResponse.split('\n')) {
        if (line.startsWith('* SEARCH')) {
          final parts = line.split(' ');
          for (int i = 2; i < parts.length; i++) {
            final id = parts[i].trim();
            if (id.isNotEmpty) {
              allIds.add(id);
            }
          }
        }
      }

      if (allIds.isEmpty) {
        print('没有找到邮件');
        return emails;
      }

      print('找到 ${allIds.length} 封邮件，正在筛选标题...');

      // 第二步：获取所有邮件的主题（批量获取）
      final matchedIds = <String>[];
      final batchSize = 50;

      for (int i = 0; i < allIds.length; i += batchSize) {
        final batch = allIds.sublist(i, min(i + batchSize, allIds.length));
        tag = _tag();
        await _sendCommand(
          '$tag FETCH ${batch.join(',')} (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])',
        );

        try {
          final response = await _readUntilTag(tag, timeout: 60);
          // 解析 FETCH 响应
          final fetchResults = _parseFetchResponse(response);
          for (final result in fetchResults) {
            final subject = result['subject'] ?? '';
            if (_matchesKeywords(subject, keywords)) {
              matchedIds.add(result['id']!);
            }
          }
        } catch (e) {
          print('批量获取标题超时，尝试单个获取...');
          // 单个获取
          for (final id in batch) {
            try {
              final stag = _tag();
              await _sendCommand(
                '$stag FETCH $id (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])',
              );
              final sresp = await _readUntilTag(stag, timeout: 30);
              final results = _parseFetchResponse(sresp);
              for (final r in results) {
                final subject = r['subject'] ?? '';
                if (_matchesKeywords(subject, keywords)) {
                  matchedIds.add(r['id']!);
                }
              }
            } catch (_) {}
          }
        }
      }

      print('标题匹配邮件: ${matchedIds.length} 封');

      // 第三步：下载匹配邮件的完整内容
      for (final id in matchedIds) {
        try {
          tag = _tag();
          await _sendCommand('$tag FETCH $id (BODY[])');
          final response = await _readUntilTag(tag, timeout: 60);

          // 解析完整的邮件内容
          final email = _parseFullEmail(response, id);
          if (email != null) {
            // 跳过回复/转发
            if (!_isReplyOrForward(email.subject)) {
              emails.add(email);
            }
          }
        } catch (e) {
          print('下载邮件 $id 失败: $e');
        }
      }

      print('最终匹配有效邮件: ${emails.length} 封');
    } catch (e) {
      print('搜索邮件出错: $e');
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
      // 匹配 * N FETCH
      final fetchMatch = RegExp(r'^\* (\d+) FETCH').firstMatch(line);
      if (fetchMatch != null) {
        // 保存前一条
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
          // 多行主题
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

    // 保存最后一条
    if (currentId != null) {
      results.add({
        'id': currentId,
        'subject': _decodeMimeHeader(subject ?? ''),
        'from': from ?? '',
        'date': date ?? '',
      });
    }

    // 去重（按ID）
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

      for (final line in lines) {
        if (inHeader && line.trim().isEmpty) {
          inHeader = false;
          inBody = true;
          continue;
        }

        if (inHeader) {
          if (line.startsWith('Subject:', caseSensitive: false)) {
            subject = _decodeMimeHeader(
              line.substring(8).trim(),
            );
          } else if (line.startsWith('From:', caseSensitive: false)) {
            from = _decodeMimeHeader(line.substring(5).trim());
          } else if (line.startsWith('To:', caseSensitive: false)) {
            to = _decodeMimeHeader(line.substring(3).trim());
          } else if (line.startsWith('Cc:', caseSensitive: false)) {
            cc = _decodeMimeHeader(line.substring(3).trim());
          } else if (line.startsWith('Date:', caseSensitive: false)) {
            date = line.substring(5).trim();
          }
        } else if (inBody) {
          bodyBuffer.writeln(line);
        }
      }

      var body = bodyBuffer.toString().trim();
      // 清理 MIME 边界和编码
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

  /// 解码 MIME 编码的标题 (如 =?UTF-8?B?...?=)
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
          // Q 编码
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
    // 移除 MIME 边界标记
    body = body.replaceAll(RegExp(r'--=_\w+'), '');
    // 移除 Content-* 头
    body = body.replaceAll(RegExp(r'^Content-.*$', multiLine: true), '');
    // 移除多余空行
    body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return body.trim();
  }

  /// 断开连接
  void disconnect() {
    try {
      if (_loggedIn) {
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