import 'dart:async';
import 'package:flutter/material.dart';
import '../models/email_model.dart';
import '../services/imap_service.dart';
import '../services/excel_service.dart';
import 'config_screen.dart';
import 'email_list_screen.dart';
import 'export_screen.dart';

/// 主页面 - 带底部导航
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
  }

  Widget _buildStatusPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态卡片
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
                      color:
                          _isConfigured ? Colors.blue.shade500 : Colors.grey,
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

          // 快捷操作
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

          // 同步进度
          if (_isSyncing)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.shade200),
              ),
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('正在同步邮件...', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),

          // 最近邮件预览
          if (_emails.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('最近邮件',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

    setState(() => _isSyncing = true);

    try {
      final service = ImapService();

      bool connected;
      if (_config.useSSL) {
        connected = await service.connectSecure(_config);
      } else {
        connected = await service.connect(_config);
      }

      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('连接失败，请检查邮箱配置'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final emails = await service.searchEmails(
        _config.keywords,
        searchDays: _config.searchDays,
        mailbox: _config.mailbox,
      );

      service.disconnect();

      if (mounted) {
        setState(() => _emails = emails);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步完成，找到 ${emails.length} 封匹配邮件'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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