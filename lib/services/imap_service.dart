import 'dart:io';
import 'dart:convert';
import '../models/email_model.dart';

typedef ProgressCallback = void Function(String message, int progress, int total);

class ImapService {
  Socket? _socket;
  String _buffer = '';
  bool _loggedIn = false;
  int _tagCounter = 0;
  String? _lastError;
  ProgressCallback? _progressCallback;

  String? get lastError => _lastError;

  void setProgressCallback(ProgressCallback callback) {
    _progressCallback = callback;
  }

  void _log(String message, {int progress = 0, int total = 0}) {
    print(message);
    _progressCallback?.call(message, progress, total);
  }

  Future<bool> connect(ImapConfig config) async {
    try {
      _lastError = null;
      _tagCounter = 0;

      _log('开始连接 IMAP 服务器...');
      _log('服务器: ${config.server}:${config.port}');
      _log('SSL: ${config.useSSL ? '开启' : '关闭'}');

      if (config.useSSL) {
        _log('正在建立安全连接...');
        _socket = await SecureSocket.connect(
          config.server,
          config.port,
          timeout: const Duration(seconds: 60),
          onBadCertificate: (cert) => true,
        );
      } else {
        _log('正在建立连接...');
        _socket = await Socket.connect(
          config.server,
          config.port,
          timeout: const Duration(seconds: 60),
        );
      }

      _log('连接成功！');
      _setupSocketListeners();

      _log('等待服务器欢迎信息...');
      final welcome = await _readResponse(timeout: 30);
      _log('服务器响应: ${welcome.substring(0, min(welcome.length, 50))}...');

      return await _login(config.username, config.password);
    } catch (e, stackTrace) {
      _lastError = '连接失败: $e';
      _log('❌ 连接失败: $e');
      print(stackTrace);
      return false;
    }
  }

  void _setupSocketListeners() {
    _socket!.listen(
      (data) {
        try {
          final decoded = utf8.decode(data);
          _buffer += decoded;
        } catch (e) {
          print('解码数据失败: $e');
        }
      },
      onError: (error) {
        _lastError = 'Socket 错误: $error';
        _log('❌ Socket 错误: $error');
      },
      onDone: () {
        _log('连接已关闭');
      },
    );
  }

  String _tag() {
    _tagCounter++;
    return 'A$_tagCounter';
  }

  Future<void> _sendCommand(String command) async {
    try {
      final data = '$command\r\n';
      _socket!.add(utf8.encode(data));
      await _socket!.flush();
    } catch (e) {
      throw Exception('发送命令失败: $e');
    }
  }

  Future<String> _readResponse({int timeout = 30}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inSeconds < timeout) {
      if (_buffer.contains('\r\n')) {
        final lines = _buffer.split('\r\n');
        _buffer = _buffer.endsWith('\r\n') ? '' : lines.removeLast();
        return lines.join('\n');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('读取响应超时（$timeout秒）');
  }

  Future<String> _readUntilTag(String tag, {int timeout = 60}) async {
    final start = DateTime.now();
    final allLines = <String>[];

    while (DateTime.now().difference(start).inSeconds < timeout) {
      if (_buffer.contains('\r\n')) {
        final lines = _buffer.split('\r\n');
        _buffer = _buffer.endsWith('\r\n') ? '' : lines.removeLast();

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

  Future<bool> _login(String username, String password) async {
    try {
      _log('正在登录...');
      _log('用户名: $username');

      final tag = _tag();
      await _sendCommand('$tag LOGIN "$username" "$password"');

      final response = await _readUntilTag(tag, timeout: 60);
      
      if (response.contains('$tag OK')) {
        _loggedIn = true;
        _log('✅ 登录成功！');
        return true;
      } else {
        _lastError = '登录失败: ${response.substring(0, min(response.length, 100))}';
        _log('❌ 登录失败');
        return false;
      }
    } catch (e) {
      _lastError = '登录异常: $e';
      _log('❌ 登录异常: $e');
      return false;
    }
  }

  String _formatSearchDate(int daysAgo) {
    final date = DateTime.now().subtract(Duration(days: daysAgo));
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day}-${months[date.month - 1]}-${date.year}';
  }

  bool _isReplyOrForward(String subject) {
    final s = subject.trim().toLowerCase();
    final prefixes = ['re:', 're：', '回复:', '回复：', 'fwd:', 'fwd：', '转发:', '转发：', 'fw:', 'fw：'];
    for (final p in prefixes) {
      if (s.startsWith(p)) {
        return true;
      }
    }
    if (subject.contains('回复:') || subject.contains('回复：') || subject.contains('Re:')) {
      return true;
    }
    return false;
  }

  bool _matchesKeywords(String subject, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final lowerSubject = subject.toLowerCase();
    for (final kw in keywords) {
      if (kw.isNotEmpty) {
        if (subject.contains(kw)) {
          return true;
        }
        if (lowerSubject.contains(kw.toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  String _decodeMimeStr(String? s) {
    if (s == null || s.isEmpty) return '';
    
    final regex = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=');
    return s.replaceAllMapped(regex, (match) {
      final encoding = match.group(2)?.toUpperCase() ?? 'B';
      final encoded = match.group(3) ?? '';

      try {
        if (encoding == 'B') {
          return utf8.decode(base64.decode(encoded));
        }
      } catch (_) {}
      return encoded;
    });
  }

  Future<List<EmailModel>> searchEmails(
    List<String> keywords, {
    int searchDays = 90,
    String mailbox = 'INBOX',
  }) async {
    if (!_loggedIn || _socket == null) {
      _lastError = '未连接到服务器';
      throw Exception('未连接到服务器');
    }

    final emails = <EmailModel>[];

    try {
      _log('选择邮箱: $mailbox');
      final selectTag = _tag();
      await _sendCommand('$selectTag SELECT "$mailbox"');
      final selectResp = await _readUntilTag(selectTag, timeout: 30);
      _log('邮箱选择成功');

      final sinceDate = _formatSearchDate(searchDays);
      _log('搜索日期范围: $sinceDate 以来');

      _log('开始搜索邮件...');
      final searchTag = _tag();
      await _sendCommand('$searchTag SEARCH SINCE $sinceDate');
      final searchResp = await _readUntilTag(searchTag, timeout: 60);

      final idList = <String>[];
      for (final line in searchResp.split('\n')) {
        if (line.startsWith('* SEARCH')) {
          final parts = line.split(' ');
          for (int i = 2; i < parts.length; i++) {
            final id = parts[i].trim();
            if (id.isNotEmpty) {
              idList.add(id);
            }
          }
        }
      }

      if (idList.isEmpty) {
        _log('未找到任何邮件');
        return emails;
      }

      _log('找到 ${idList.length} 封邮件，开始筛选...');

      final matchedIds = <String>[];
      int processed = 0;

      for (final mid in idList) {
        processed++;
        if (processed > 1000) break;

        try {
          final hdrTag = _tag();
          await _sendCommand('$hdrTag FETCH $mid (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM TO DATE)])');
          final hdrResp = await _readUntilTag(hdrTag, timeout: 30);

          String? subject;
          String? sender;
          String? recipient;
          String? dateStr;

          final lines = hdrResp.split('\n');
          for (final line in lines) {
            final lineLower = line.toLowerCase();
            if (lineLower.startsWith('subject:')) {
              subject = _decodeMimeStr(line.substring(8).trim());
            } else if (lineLower.startsWith('from:')) {
              sender = _decodeMimeStr(line.substring(5).trim());
            } else if (lineLower.startsWith('to:')) {
              recipient = _decodeMimeStr(line.substring(3).trim());
            } else if (lineLower.startsWith('date:')) {
              dateStr = line.substring(5).trim();
            }
          }

          if (subject != null && subject.isNotEmpty) {
            if (_isReplyOrForward(subject)) {
              continue;
            }
            if (_matchesKeywords(subject, keywords)) {
              matchedIds.add(mid);
            }
          }
        } catch (e) {
          continue;
        }

        if (processed % 50 == 0) {
          _log('筛选进度: $processed/${idList.length}，已匹配 ${matchedIds.length} 封', 
              progress: processed, total: idList.length);
        }
      }

      _log('匹配到 ${matchedIds.length} 封符合条件的邮件');

      if (matchedIds.isEmpty) {
        _log('没有找到匹配关键词的邮件');
        return emails;
      }

      _log('开始获取完整邮件内容...');

      for (int i = 0; i < matchedIds.length; i++) {
        final mid = matchedIds[i];
        try {
          final fullTag = _tag();
          await _sendCommand('$fullTag FETCH $mid (RFC822)');
          final fullResp = await _readUntilTag(fullTag, timeout: 120);

          final email = _parseFullEmail(fullResp, mid);
          if (email != null) {
            emails.add(email);
          }
        } catch (e) {
          continue;
        }

        _log('获取进度: ${i + 1}/${matchedIds.length}', 
            progress: i + 1, total: matchedIds.length);
      }

      _log('✅ 完成！共获取 ${emails.length} 封邮件');
      return emails;
    } catch (e) {
      _lastError = '搜索邮件出错: $e';
      _log('❌ 搜索邮件出错: $e');
      rethrow;
    }
  }

  EmailModel? _parseFullEmail(String response, String id) {
    try {
      String? subject;
      String? sender;
      String? recipient;
      String? date;
      final bodyBuffer = StringBuffer();

      final lines = response.split('\n');
      bool inHeader = true;
      bool inBody = false;

      for (final line in lines) {
        final lineLower = line.toLowerCase();
        
        if (inHeader && line.trim().isEmpty) {
          inHeader = false;
          inBody = true;
          continue;
        }

        if (inHeader) {
          if (lineLower.startsWith('subject:')) {
            subject = _decodeMimeStr(line.substring(8).trim());
          } else if (lineLower.startsWith('from:')) {
            sender = _decodeMimeStr(line.substring(5).trim());
          } else if (lineLower.startsWith('to:')) {
            recipient = _decodeMimeStr(line.substring(3).trim());
          } else if (lineLower.startsWith('date:')) {
            date = line.substring(5).trim();
          }
        } else if (inBody) {
          if (line.trim().startsWith('Content-') || 
              line.trim().startsWith('--') ||
              line.trim().startsWith('Content-Type')) {
            continue;
          }
          bodyBuffer.writeln(line);
        }
      }

      var body = bodyBuffer.toString().trim();
      body = body.replaceAll(RegExp(r'--=_\w+'), '');
      body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n');

      return EmailModel(
        subject: subject ?? '(无主题)',
        from: sender ?? '未知',
        to: recipient ?? '',
        cc: '',
        date: date ?? '',
        body: body,
      );
    } catch (e) {
      print('解析邮件 $id 失败: $e');
      return null;
    }
  }

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