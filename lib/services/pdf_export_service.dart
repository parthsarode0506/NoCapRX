import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pgx_report.dart';

class PdfExportService {
  /// Generates a formatted PDF document for a PgxMultiReport.
  static Future<Uint8List> generatePdfReport(PgxMultiReport report) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'PharmaGuard (OnDeviceRx)',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.Text(
                    'Pharmacogenomic Risk Report',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.blue900, thickness: 1.5),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Metadata Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Patient ID: ${report.patientId}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.Text('VCF Source: ${report.vcfFilename}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Report ID: ${report.reportId}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Generated: ${report.timestamp.split('T').first}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              'Drug Safety & Clinical Risk Summary',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 8),

            // Drug Cards
            ...report.drugReports.map((d) => _buildPdfDrugCard(d)),

            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 8),

            // Notice
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'PRIVACY & CLINICAL NOTICE: Raw genetic VCF file content remained 100% on the local client device during evaluation. This pharmacogenomic risk prediction report is generated using on-device CPIC guidelines for clinical decision support.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPdfDrugCard(PgxReport d) {
    PdfColor headerColor = PdfColors.green700;
    if (d.riskAssessment.riskLabel == 'Adjust Dosage') headerColor = PdfColors.orange800;
    if (d.riskAssessment.riskLabel == 'Toxic' || d.riskAssessment.riskLabel == 'Ineffective') headerColor = PdfColors.red800;
    if (d.riskAssessment.riskLabel == 'Unknown') headerColor = PdfColors.grey700;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: headerColor, width: 1),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${d.drug} (${d.pharmacogenomicProfile.primaryGene})',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: headerColor,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  d.riskAssessment.riskLabel.toUpperCase(),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('Diplotype: ${d.pharmacogenomicProfile.diplotype} | Phenotype: ${d.pharmacogenomicProfile.phenotype} | Confidence: ${(d.riskAssessment.confidenceScore * 100).toInt()}%',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
          pw.SizedBox(height: 4),
          pw.Text('Recommendation: ${d.clinicalRecommendation.dosingRecommendation}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          if (d.clinicalRecommendation.alternativeDrugs.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text('Alternative Drugs: ${d.clinicalRecommendation.alternativeDrugs.join(', ')}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800)),
          ],
          pw.SizedBox(height: 4),
          pw.Text('Patient Summary: ${d.llmGeneratedExplanation.patientFriendly}',
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey900)),
        ],
      ),
    );
  }

  /// Exports and shares the PDF report via native share sheet.
  static Future<void> sharePdfReport(PgxMultiReport report) async {
    final pdfBytes = await generatePdfReport(report);
    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/PharmaGuard_Report_${report.reportId}.pdf');
    await file.writeAsBytes(pdfBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'PharmaGuard Pharmacogenomic Risk Report #${report.reportId}',
    );
  }

  /// Prints or opens PDF print preview.
  static Future<void> printPdfReport(PgxMultiReport report) async {
    final pdfBytes = await generatePdfReport(report);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'PharmaGuard_Report_${report.reportId}',
    );
  }
}
