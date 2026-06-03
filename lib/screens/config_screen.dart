import 'package:flutter/material.dart';
import '../models/email_model.dart';

/// 配置页面
class ConfigScreen extends StatefulWidget {
  final ImapConfig config;
  final Function(ImapConfig) onSaved;

  const ConfigScreen({
    super.key,
    required this.config,
    required this.onSaved,
  });

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late TextEditingController _serverCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _mailboxCtrl;
  late TextEditingController _keywordsCtrl;
  late TextEditingController _daysCtrl;
  bool _useSSL = true;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: widget.config.server);
    _portCtrl = TextEditingController(text: widget.config.port.toString());
    _userCtrl = TextEditingController(text: widget.config.username);
    _passCtrl = TextEditingController(text: widget.config.password);
    _mailboxCtrl = TextEditingController(text: widget.config.mailbox);
    _keywordsCtrl = TextEditingController(
      text: widget.config.keywords.join(','),
    );
    _daysCtrl = TextEditingController(
      text: widget.config.searchDays.toString(),
    );
    _useSSL = widget.config.useSSL;
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _mailboxCtrl.dispose();
    _keywordsCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final config = ImapConfig(
      server: _serverCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 993,
      useSSL: _useSSL,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      mailbox: _mailboxCtrl.text.trim().isEmpty
          ? 'INBOX'
          : _mailboxCtrl.text.trim(),
      keywords: _keywordsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      searchDays: int.tryParse(_daysCtrl.text) ?? 30,
    );

    if (config.username.isEmpty || config.password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱地址和密码/授权码')),
      );
      return;
    }

    widget.onSaved(config);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邮箱配置'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('📮 IMAP 服务器配置', [
            _buildField('服务器地址', _serverCtrl,
                hint: 'imap.qq.com', icon: Icons.dns),
            _buildField('端口', _portCtrl, hint: '993', icon: Icons.numbers),
            SwitchListTile(
              title: const Text('使用 SSL'),
              subtitle: const Text('993 端口默认使用 SSL'),
              value: _useSSL,
              onChanged: (v) => setState(() => _useSSL = v),
              secondary: const Icon(Icons.lock),
            ),
          ]),
          const SizedBox(height: 12),
          _buildSection('🔑 账号信息', [
            _buildField('邮箱地址', _userCtrl,
                hint: 'your@email.com', icon: Icons.email),
            _buildField('密码/授权码', _passCtrl,
                hint: 'IMAP 授权码',
                icon: Icons.key,
                obscure: true),
          ]),
          const SizedBox(height: 12),
          _buildSection('⚙️ 其他设置', [
            _buildField('邮箱文件夹', _mailboxCtrl,
                hint: 'INBOX', icon: Icons.folder),
            _buildField('搜索天数', _daysCtrl,
                hint: '30', icon: Icons.calendar_today),
          ]),
          const SizedBox(height: 12),
          _buildSection('🏷️ 筛选关键词', [
            _buildField('关键词（逗号分隔）', _keywordsCtrl,
                hint: '会议纪要,通知,报告,项目',
                icon: Icons.label,
                multiline: true),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存配置', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl,
      {String? hint, IconData? icon, bool obscure = false, bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: ctrl,
        obscureText: obscure ? _obscurePass : false,
        maxLines: multiline ? 3 : 1,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
          suffixIcon: obscure
              ? IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}