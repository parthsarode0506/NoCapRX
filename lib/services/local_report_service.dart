import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pgx_report.dart';

class LocalReportService {
  static const _key = 'saved_pgx_reports';

  static Future<List<PgxMultiReport>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getStringList(_key) ?? const <String>[];
    final reports = <PgxMultiReport>[];
    for (final item in encoded) {
      try {
        reports.add(
          PgxMultiReport.fromJson(jsonDecode(item) as Map<String, dynamic>),
        );
      } on FormatException {
        // Ignore only a corrupt individual cached report.
      } on TypeError {
        // Ignore only a corrupt individual cached report.
      }
    }
    return reports;
  }

  static Future<void> save(PgxMultiReport report) async {
    final reports = await load();
    final index = reports.indexWhere((item) => item.reportId == report.reportId);
    if (index == -1) {
      reports.add(report);
    } else {
      reports[index] = report;
    }
    await _write(reports);
  }

  static Future<void> delete(String reportId) async {
    final reports = await load();
    reports.removeWhere((report) => report.reportId == reportId);
    await _write(reports);
  }

  static Future<void> _write(List<PgxMultiReport> reports) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key,
      reports.map((report) => jsonEncode(report.toJson())).toList(),
    );
  }
}
