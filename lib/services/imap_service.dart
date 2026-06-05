import 'dart:io';
import 'dart:convert';
import 'dart:math';
import '../models/email_model.dart';

/// IMAP 邮件同步服务 - 参考 Python 旧项目实现
class ImapService {
  Socket? _socket;
  String _buffer = '';
  bool _loggedIn = false;
  int _tagCounter = 0;
  String? _lastError;

  String? get lastError => _lastError;

  /// 连接到 IMAP 服务器
  Future<bool> connect(ImapConfig config) async {
    try {
      _lastError = null;
      _tagCounter = 0;

      print('连接邮箱 ${config.server} ...');
      
      if (config.useSSL) {
        _socket = await SecureSocket.connect(
          config.server,
          config.port,
          timeout: const Duration(seconds: 60),
          onBadCertificate: (cert) => true,
        );
      } else {
        _socket = await Socket.connect(
          config.server,
          config.port,
          timeout: const Duration(seconds: 60),
        );
      }

      _setupSocketListeners();

      // 等待欢迎信息
      final welcome = await _readResponse(timeout: 30);
      print('服务器响应: $welcome');

      // 登录
      return await _login(config.username, config.password);
    } catch (e, stackTrace) {
      _lastError = '连接失败: $e\n$stackTrace';
      print(_lastError);
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
        print(_lastError);
      },
      onDone: () {
        print('Socket 连接关闭');
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
      print('发送命令: $command');
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

  Future<String> _readUntilTag(String tag, {int timeout = 60}) async {
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

  Future<bool> _login(String username, String password) async {
    try {
      final tag = _tag();
      await _sendCommand('$tag LOGIN "$username" "$password"');

      final response = await _readUntilTag(tag, timeout: 60);
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
    // 额外检查主题中是否包含回复相关内容
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
    
    // 简单的 MIME 解码处理
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

  /// 搜索邮件 - 参考 Python 旧项目
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
      // 选择邮箱（只读）
      final selectTag = _tag();
      await _sendCommand('$selectTag SELECT "$mailbox"');
      final selectResp = await _readUntilTag(selectTag, timeout: 30);
      print('已选择邮箱: $mailbox');

      // 计算搜索日期
      final sinceDate = _formatSearchDate(searchDays);
      print('搜索日期: $sinceDate 以来');

      // 搜索邮件
      final searchTag = _tag();
      await _sendCommand('$searchTag SEARCH SINCE $sinceDate');
      final searchResp = await _readUntilTag(searchTag, timeout: 60);
      print('搜索响应: $searchResp');

      // 解析邮件 ID
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
        print('没有找到邮件');
        return emails;
      }

      print('共 ${idList.length} 封邮件，开始筛选...');

      // 第一遍：获取头部信息筛选
      final matchedIds = <String>[];
      int processed = 0;

      for (final mid in idList) {
        processed++;
        if (processed > 1000) break; // 上限1000封

        try {
          // 获取头部信息
          final hdrTag = _tag();
          await _sendCommand('$hdrTag FETCH $mid (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM TO DATE)])');
          final hdrResp = await _readUntilTag(hdrTag, timeout: 30);

          // 解析头部
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
            // 去回复/转发
            if (_isReplyOrForward(subject)) {
              continue;
            }
            // 关键词匹配
            if (_matchesKeywords(subject, keywords)) {
              matchedIds.add(mid);
            }
          }
        } catch (e) {
          print('获取头部失败 $mid: $e');
          continue;
        }

        if (processed % 50 == 0) {
          print('  进度 $processed/${idList.length}，已匹配 ${matchedIds.length}...');
        }
      }

      print('匹配到 ${matchedIds.length} 封邮件，开始获取完整内容...');

      // 第二遍：获取完整邮件内容
      for (final mid in matchedIds) {
        try {
          final fullTag = _tag();
          await _sendCommand('$fullTag FETCH $mid (RFC822)');
          final fullResp = await _readUntilTag(fullTag, timeout: 120);

          // 解析完整邮件
          final email = _parseFullEmail(fullResp, mid);
          if (email != null) {
            emails.add(email);
          }
        } catch (e) {
          print('获取完整邮件失败 $mid: $e');
          continue;
        }
      }

      print('最终匹配有效邮件: ${emails.length} 封');
      return emails;
    } catch (e, stackTrace) {
      _lastError = '搜索邮件出错: $e\n$stackTrace';
      print(_lastError);
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

      // 先解析头部
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
          // 跳过 MIME 头
          if (line.trim().startsWith('Content-') || 
              line.trim().startsWith('--') ||
              line.trim().startsWith('Content-Type')) {
            continue;
          }
          bodyBuffer.writeln(line);
        }
      }

      var body = bodyBuffer.toString().trim();
      // 清理
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
