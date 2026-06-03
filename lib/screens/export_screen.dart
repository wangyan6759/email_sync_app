import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/email_model.dart';
import '../services/excel_service.dart';

/// 导出页面
class ExportScreen extends StatefulWidget {
  final List<EmailModel> emails;

  const ExportScreen({super.key, required this.emails});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;
  List<Map<String, dynamic>> _exportedFiles = [];
  String? _lastExportedPath;

  @override
  void initState() {
    super.initState();
    _loadExportedFiles();
  }

  Future<void> _loadExportedFiles() async {
    final files = await ExcelService.getExportedFiles();
    if (mounted) {
      setState(() => _exportedFiles = files);
    }
  }

  Future<void> _export() async {
    if (widget.emails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可导出的邮件，请先同步')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final path = await ExcelService.exportToExcel(widget.emails, null);
      _lastExportedPath = path;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出成功！共 ${widget.emails.length} 封邮件'),
            backgroundColor: Colors.green,
          ),
        );
        _loadExportedFiles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(path)]);
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      await file.delete();
      _loadExportedFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件已删除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 导出操作卡片
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.table_chart_outlined,
                        size: 32, color: Colors.green.shade600),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '导出到 Excel',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.emails.isEmpty
                        ? '暂无邮件数据'
                        : '将 ${widget.emails.length} 封邮件导出为 Excel 文件\n包含「邮件数据」和「关键信息提取」两个工作表',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isExporting ? null : _export,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.file_download),
                      label: Text(
                        _isExporting ? '正在导出...' : '生成 Excel 文件',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 导出历史
          const Text('历史导出文件',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (_exportedFiles.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('暂无导出文件',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            )
          else
            ..._exportedFiles.map((f) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.description,
                          color: Colors.green.shade600, size: 24),
                    ),
                    title: Text(
                      f['name'] as String,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      ExcelService.formatSize(f['size'] as int),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share, size: 20),
                          onPressed: () => _shareFile(f['path'] as String),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: () => _deleteFile(f['path'] as String),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}