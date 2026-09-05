import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/genomic_drug_scan_report.dart';
import '../models/pgx_report.dart';

class PdfReportService {
  static Future<File> generateGenomicDrugSafetyPdf(
    GenomicDrugScanReport report,
  ) async {
    if (report.patientId.trim().isEmpty) {
      throw ArgumentError('Patient ID is required to generate the report.');
    }
    if (report.timestamp.trim().isEmpty) {
      throw ArgumentError('Analysis timestamp is required to generate the report.');
    }

    final pdf = pw.Document();
    final genes = report.parseResult.geneProfiles.values.toList();
    final actionable = report.actionableReports;
    final highRisk = actionable
        .where((r) => r.riskAssessment.riskLabel == 'Toxic')
        .toList();
    final doseAdjustments = actionable
        .where((r) => r.riskAssessment.riskLabel == 'Adjust Dosage')
        .toList();
    final reducedEfficacy = actionable
        .where((r) => r.riskAssessment.riskLabel == 'Ineffective')
        .toList();
    final noActionable = report.drugReports
        .where((r) => r.riskAssessment.riskLabel == 'Safe')
        .toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'PHARMAGUARD',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            pw.Text(
              'Pharmacogenomic Drug Safety Report',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(color: PdfColors.blue900),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated: ${report.timestamp.split('T').first}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (_) => [
          pw.Text(
            'PHARMACOGENOMIC DRUG SAFETY REPORT',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Personalized Genomic Medication Assessment',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          _table([
            ['Patient ID', _value(report.patientId)],
            ['VCF Filename', _value(report.vcfFilename)],
            ['Analysis Date', _value(report.timestamp)],
          ]),
          _sectionTitle('EXECUTIVE SUMMARY'),
          _table([
            ['Genes analyzed', '${genes.length}'],
            ['Variants detected', '${report.parseResult.qualityMetrics.variantsDetected}'],
            ['PGx genes evaluated', '${genes.length}'],
            ['High-risk findings', '${highRisk.length}'],
            ['Dose-adjustment findings', '${doseAdjustments.length}'],
            ['Reduced-efficacy findings', '${reducedEfficacy.length}'],
            ['No-actionable findings', '${noActionable.length}'],
          ]),
          _sectionTitle('GENOMIC PROFILE'),
          _genomicProfileTable(genes),
          _sectionTitle('HIGH-RISK / ACTIONABLE FINDINGS'),
          _findingTable(
            highRisk.isEmpty ? actionable : highRisk,
            includeEvidence: true,
          ),
          _sectionTitle('DOSE / THERAPY ADJUSTMENT FINDINGS'),
          _findingTable(doseAdjustments),
          _sectionTitle('REDUCED EFFICACY FINDINGS'),
          _findingTable(reducedEfficacy, includeEvidence: true),
          _sectionTitle('COMPLETE PHARMACOGENOMIC PROFILE'),
          ...genes.map(
            (gene) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    gene.gene,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Variants: ${_value(gene.variants.map((v) => v.rsid).join(', '))}'),
                  pw.Text('Genotype: Not available'),
                  pw.Text('Diplotype: ${_value(gene.diplotype)}'),
                  pw.Text('Phenotype: ${_value(gene.phenotype)}'),
                ],
              ),
            ),
          ),
          if (genes.isEmpty)
            pw.Text('No pharmacogenomic genes were available in this report.'),
          _sectionTitle('IMPORTANT MEDICAL DISCLAIMER'),
          pw.Text(
            'This report is a pharmacogenomic decision-support report. It is not a diagnosis or prescription. '
            'Do not start, stop, or change medication or dosage solely on the basis of this report. '
            'Discuss actionable findings with a qualified doctor, pharmacist, or clinical pharmacologist. '
            'A normal pharmacogenomic result does not guarantee that a medicine is safe for every person because '
            'allergies, drug interactions, medical conditions, dose, and other clinical factors may affect medication safety.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/PharmaGuard_${report.reportId}.pdf');
      await file.writeAsBytes(await pdf.save(), flush: true);
      if (!await file.exists()) {
        throw StateError('PDF file was not created.');
      }
      return file;
    } catch (error) {
      throw Exception('Unable to save the PDF report: $error');
    }
  }

  static Future<void> sharePdf(File file) async {
    if (!await file.exists()) {
      throw StateError('The PDF file no longer exists.');
    }
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: file.uri.pathSegments.last,
    );
  }

  static Future<void> openPdf(File file) async {
    if (!await file.exists()) {
      throw StateError('The PDF file no longer exists.');
    }
    await Printing.layoutPdf(onLayout: (_) => file.readAsBytes());
  }

  static pw.Widget _sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
      );

  static pw.Widget _table(List<List<String>> rows) => pw.TableHelper.fromTextArray(
        headers: const ['Field', 'Value'],
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellPadding: const pw.EdgeInsets.all(5),
        border: pw.TableBorder.all(color: PdfColors.grey400),
      );

  static pw.Widget _genomicProfileTable(List<dynamic> genes) {
    final rows = genes.map<List<String>>((gene) {
      final variants = (gene.variants as List)
          .map((variant) => '${variant.rsid} (${_value(variant.starAllele)})')
          .join(', ');
      return [
        _value(gene.gene),
        _value(variants),
        'Not available',
        _value(gene.diplotype),
        _value(gene.phenotype),
      ];
    }).toList();
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Gene',
        'Variant / Star Allele',
        'Genotype',
        'Diplotype',
        'Phenotype',
      ],
      data: rows.isEmpty
          ? [
              [
                'Not available',
                'Not available',
                'Not available',
                'Not available',
                'Not available',
              ]
            ]
          : rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.all(4),
      border: pw.TableBorder.all(color: PdfColors.grey400),
    );
  }

  static pw.Widget _findingTable(
    List<PgxReport> reports, {
    bool includeEvidence = false,
  }) {
    if (reports.isEmpty) {
      return pw.Text('No findings in this category.');
    }
    final rows = reports.map((drug) {
      final profile = drug.pharmacogenomicProfile;
      final recommendation = drug.clinicalRecommendation;
      return [
        _value(drug.drug),
        _value(profile.primaryGene),
        _value(profile.detectedVariants.map((v) => v.rsid).join(', ')),
        'Not available',
        _value(profile.diplotype),
        _value(profile.phenotype),
        _value(drug.riskAssessment.riskLabel),
        _value(recommendation.dosingRecommendation),
        if (includeEvidence)
          _value(recommendation.evidenceSource.isNotEmpty
              ? recommendation.evidenceSource
              : recommendation.cpicGuidelineCitation),
      ];
    }).toList();
    return pw.TableHelper.fromTextArray(
      headers: [
        'Drug',
        'Gene',
        'Variant',
        'Genotype',
        'Diplotype',
        'Phenotype',
        'Risk',
        'Finding / Recommendation',
        if (includeEvidence) 'Evidence',
      ],
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.all(3),
      border: pw.TableBorder.all(color: PdfColors.grey400),
    );
  }

  static String _value(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Not available' : text;
  }
}
