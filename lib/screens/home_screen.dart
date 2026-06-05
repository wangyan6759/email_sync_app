import 'dart:async';
import 'package:flutter/material.dart';
import '../models/email_model.dart';
import '../services/imap_service.dart';
import '../services/excel_service.dart';
import 'config_screen.dart';
import 'email_list_screen.dart';
import 'export_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  ImapConfig _config = ImapConfig();
  List<EmailModel> _emails = [];
  bool _isSyncing = false;
  bool _isConfigured = false;
  List<String> _syncLogs = [];
  int _progress = 0;
  int _total = 0;

  final _pages = <Widget>[];
  final _pageKeys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      _buildStatusPage(),
      EmailListScreen(emails: _emails),
      ExportScreen(emails: _emails),
    ]);
    _checkConfig();
  }

  void _checkConfig() {
    if (_config.username.isNotEmpty && _config.password.isNotEmpty) {
      setState(() => _isConfigured = true);
    }
  }

  void _addLog(String message) {
    setState(() {
      _syncLogs.add(message);
    });
  }

  void _updateProgress(int progress, int total) {
    setState(() {
      _progress = progress;
      _total = total;
    });
  }

  Widget _buildStatusPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _isConfigured
                          ? Colors.blue.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _isConfigured
                          ? Icons.mark_email_read
                          : Icons.email_outlined,
                      size: 36,
                      color: _isConfigured ? Colors.blue.shade500 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isConfigured ? '邮件同步助手' : '请先配置邮箱',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _emails.isEmpty
                        ? '已同步 0 封邮件'
                        : '已同步 ${_emails.length} 封邮件',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: Icons.settings,
                  label: '邮箱配置',
                  color: Colors.blue,
                  onTap: () => _openConfig(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  icon: Icons.sync,
                  label: '同步邮件',
                  color: Colors.green,
                  onTap: _isConfigured ? () => _startSync() : _openConfig,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  icon: Icons.file_download,
                  label: '导出Excel',
                  color: Colors.orange,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_isSyncing) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.shade200),
              ),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        const Text('正在同步邮件...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    if (_total > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _total > 0 ? _progress / _total : null,
                        backgroundColor: Colors.blue.shade100,
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${_progress}/${_total}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('同步日志', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _syncLogs.length,
                        itemBuilder: (context, index) {
                          final log = _syncLogs[_syncLogs.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              log,
                              style: TextStyle(
                                fontSize: 12,
                                color: log.contains('✅') ? Colors.green 
                                    : log.contains('❌') ? Colors.red 
                                    : Colors.grey.shade700,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_emails.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('最近邮件',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () => setState(() => _currentIndex = 1),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            ..._emails.take(5).map((email) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(email.subject,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(email.from,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                    trailing: Text(
                      email.date.length > 10
                          ? email.date.substring(0, 10)
                          : email.date,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                    onTap: () {},
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openConfig() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConfigScreen(
          config: _config,
          onSaved: (config) {
            _config = config;
            setState(() => _isConfigured = true);
          },
        ),
      ),
    );
    if (result == true) {
      setState(() => _isConfigured = true);
    }
  }

  Future<void> _startSync() async {
    if (!_isConfigured) return;

    setState(() {
      _isSyncing = true;
      _syncLogs = [];
      _progress = 0;
      _total = 0;
    });

    try {
      _addLog('📧 开始同步邮件...');

      final service = ImapService();
      service.setProgressCallback((message, progress, total) {
        _addLog(message);
        _updateProgress(progress, total);
      });

      _addLog('🔌 正在连接服务器...');
      final connected = await service.connect(_config);

      if (!connected) {
        final errorMsg = service.lastError ?? '连接失败，请检查邮箱配置';
        _addLog('❌ $errorMsg');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
        }
        return;
      }

      _addLog('🔍 正在搜索邮件...');
      final emails = await service.searchEmails(
        _config.keywords,
        searchDays: _config.searchDays,
        mailbox: _config.mailbox,
      );

      service.disconnect();

      if (mounted) {
        setState(() => _emails = emails);
        _addLog('✅ 同步完成！找到 ${emails.length} 封匹配邮件');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步完成，找到 ${emails.length} 封匹配邮件'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _addLog('❌ 同步失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邮件同步助手'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openConfig,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildStatusPage(),
          EmailListScreen(emails: _emails, totalCount: _emails.length),
          ExportScreen(emails: _emails),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.email_outlined),
            selectedIcon: Icon(Icons.email),
            label: '邮件',
          ),
          NavigationDestination(
            icon: Icon(Icons.file_download_outlined),
            selectedIcon: Icon(Icons.file_download),
            label: '导出',
          ),
        ],
      ),
    );
  }
}