import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../models/email_model.dart';
import 'email_extractor.dart';

/// Excel 导出服务
class ExcelService {
  static Future<String> exportToExcel(
    List<EmailModel> emails,
    List<ExtractedInfo>? extractedInfos,
  ) async {
    final excel = Excel.createExcel();
    extractedInfos ??= EmailExtractorService.extractAll(emails);

    // Sheet 1: 邮件数据
    final sheet1 = excel['邮件数据'];
    sheet1.appendRow([
      TextCellValue('序号'),
      TextCellValue('主题'),
      TextCellValue('发件人'),
      TextCellValue('收件人'),
      TextCellValue('日期'),
      TextCellValue('正文预览'),
    ]);

    _styleHeader(sheet1, 0, 6);

    for (int i = 0; i < emails.length; i++) {
      final e = emails[i];
      sheet1.appendRow([
        TextCellValue((i + 1).toString()),
        TextCellValue(e.subject),
        TextCellValue(e.from),
        TextCellValue(e.to),
        TextCellValue(e.date),
        TextCellValue(e.bodyPreview),
      ]);
    }

    sheet1.setColumnWidth(0, 8);
    sheet1.setColumnWidth(1, 50);
    sheet1.setColumnWidth(2, 30);
    sheet1.setColumnWidth(3, 30);
    sheet1.setColumnWidth(4, 25);
    sheet1.setColumnWidth(5, 60);

    // Sheet 2: 关键信息提取
    final sheet2 = excel['关键信息提取'];
    sheet2.appendRow([
      TextCellValue('序号'),
      TextCellValue('主题'),
      TextCellValue('发件人'),
      TextCellValue('日期'),
      TextCellValue('紧急程度'),
      TextCellValue('摘要'),
      TextCellValue('关键要点'),
      TextCellValue('待办事项'),
      TextCellValue('相关人员'),
      TextCellValue('提及日期'),
    ]);

    _styleHeader(sheet2, 0, 10);

    for (int i = 0; i < extractedInfos.length; i++) {
      final info = extractedInfos[i];
      sheet2.appendRow([
        TextCellValue((i + 1).toString()),
        TextCellValue(info.subject),
        TextCellValue(info.from),
        TextCellValue(info.date),
        TextCellValue(info.urgencyLevel),
        TextCellValue(info.summary),
        TextCellValue(info.keyPoints),
        TextCellValue(info.actionItems),
        TextCellValue(info.mentionedPeople),
        TextCellValue(info.mentionedDates),
      ]);
    }

    sheet2.setColumnWidth(0, 8);
    sheet2.setColumnWidth(1, 45);
    sheet2.setColumnWidth(2, 25);
    sheet2.setColumnWidth(3, 20);
    sheet2.setColumnWidth(4, 10);
    sheet2.setColumnWidth(5, 50);
    sheet2.setColumnWidth(6, 45);
    sheet2.setColumnWidth(7, 45);
    sheet2.setColumnWidth(8, 20);
    sheet2.setColumnWidth(9, 20);

    final fileBytes = excel.encode();
    if (fileBytes == null) throw Exception('Excel encoding failed');

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'email_export_$timestamp.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(fileBytes);
    return file.path;
  }

  static Future<List<Map<String, dynamic>>> getExportedFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = <Map<String, dynamic>>[];
    if (await dir.exists()) {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.xlsx')) {
          final stat = await entity.stat();
          files.add({
            'name': entity.path.split(Platform.pathSeparator).last,
            'path': entity.path,
            'size': stat.size,
            'created': stat.modified.toIso8601String(),
          });
        }
      }
    }
    files.sort((a, b) => b['created'].compareTo(a['created']));
    return files;
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static void _styleHeader(Sheet sheet, int startCol, int endCol) {
    final cellStyle = CellStyle(bold: true);
    for (int col = startCol; col < endCol; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: 0,
      ));
      cell.cellStyle = cellStyle;
    }
  }
}