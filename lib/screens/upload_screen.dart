import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/app_providers.dart';
import '../parser/vcf_parser.dart';
import '../services/genomic_drug_scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'genomic_scan_screen.dart';
import 'drug_input_screen.dart';
import 'home_screen.dart';

class UploadScreen extends ConsumerStatefulWidget {
  final bool returnToMedicine;
  final bool returnToDashboard;

  const UploadScreen({
    super.key,
    this.returnToMedicine = false,
    this.returnToDashboard = true,
  });

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String? _errorMessage;
  bool _isValid = false;
  bool _isProcessing = false;

  Future<void> _pickVcfFile() async {
    setState(() {
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vcf'],
        // Web browsers cannot supply PlatformFile.path. Request the file bytes
        // explicitly so parsing stays fully on-device on every platform.
      );

      if (files.isNotEmpty) {
        final platformFile = files.first;
        final name = platformFile.name;

        if (!name.toLowerCase().endsWith('.vcf')) {
          _setError('Invalid file extension. Please select a .vcf file.');
          return;
        }

        final bytes = await platformFile.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          _setError('File size exceeds the 5MB limit.');
          return;
        }

        final content = utf8.decode(bytes);

        if (content.trim().isEmpty) {
          _setError('The selected VCF file is empty.');
          return;
        }

        // Validate content with VCF parser
        final parseResult = VcfParser.parseVcfContent(content);

        ref.read(selectedVcfFilenameProvider.notifier).state = name;
        ref.read(selectedVcfContentProvider.notifier).state = content;
        ref.read(vcfParseResultProvider.notifier).state = parseResult;
        ref.read(genomicScanReportProvider.notifier).state = GenomicDrugScanService.scan(
          parseResult: parseResult,
          vcfFilename: name,
        );

        setState(() {
          _isValid = true;
          _errorMessage = null;
        });

        if (widget.returnToMedicine && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DrugInputScreen()),
          );
        } else if (widget.returnToDashboard && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      _setError('VCF Parsing Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _setError(String msg) {
    ref.read(selectedVcfFilenameProvider.notifier).state = null;
    ref.read(selectedVcfContentProvider.notifier).state = null;
    ref.read(vcfParseResultProvider.notifier).state = null;
    setState(() {
      _errorMessage = msg;
      _isValid = false;
    });
  }

  void _removeFile() {
    ref.read(selectedVcfFilenameProvider.notifier).state = null;
    ref.read(selectedVcfContentProvider.notifier).state = null;
    ref.read(vcfParseResultProvider.notifier).state = null;
    setState(() {
      _errorMessage = null;
      _isValid = false;
    });
  }

  void _scanAllDrugRisks() {
    final parseResult = ref.read(vcfParseResultProvider);
    final filename = ref.read(selectedVcfFilenameProvider);
    if (parseResult == null || filename == null) return;
    final report = GenomicDrugScanService.scan(
      parseResult: parseResult,
      vcfFilename: filename,
    );
    ref.read(genomicScanReportProvider.notifier).state = report;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GenomicScanScreen(report: report)),
    );
  }

  void _checkMedicine() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DrugInputScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filename = ref.watch(selectedVcfFilenameProvider);
    final parseResult = ref.watch(vcfParseResultProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Upload genetic data')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntro(theme),
              const SizedBox(height: 20),
              _buildDropzone(theme),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                NoticeBanner(tone: NoticeTone.danger, message: _errorMessage!),
                const SizedBox(height: 16),
              ],
              if (_isValid && filename != null) ...[
                _buildFileCard(theme, filename, parseResult),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isProcessing ? null : _checkMedicine,
                  icon: const Icon(Icons.medication_outlined),
                  label: const Text('Check a medicine'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _scanAllDrugRisks,
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('Check all my medication risks'),
                ),
                const SizedBox(height: 16),
              ],
              const NoticeBanner(
                tone: NoticeTone.info,
                title: 'On-device by design',
                message:
                    'Your VCF is parsed on this device. Only the derived gene '
                    'result is used for the checks — the raw file never leaves '
                    'your phone.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: const Icon(Icons.biotech_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analyze your genetic profile',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Upload your VCF file to find gene–medicine interactions '
                'relevant to you.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDropzone(ThemeData theme) {
    final activeColor = _isValid ? AppTheme.safeGreen : AppTheme.accentEmerald;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : _pickVcfFile,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: activeColor.withValues(alpha: 0.55), width: 1.6),
          ),
          child: _isProcessing
              ? Column(
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 16),
                    Text('Reading file…', style: theme.textTheme.titleMedium),
                  ],
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isValid
                            ? Icons.check_circle_rounded
                            : Icons.upload_file_rounded,
                        size: 40,
                        color: activeColor,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isValid
                          ? 'File loaded and validated'
                          : 'Tap to choose a .vcf file',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _isValid ? AppTheme.safeGreen : AppTheme.primaryEmerald,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'VCF v4.2 · up to 5 MB',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFileCard(
    ThemeData theme,
    String filename,
    dynamic parseResult,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.infoBlueBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppTheme.infoBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.dangerRed),
                onPressed: _removeFile,
                tooltip: 'Remove file',
              ),
            ],
          ),
          if (parseResult != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                Text(
                  'Parsing quality',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                PillBadge(
                  label:
                      '${(parseResult.qualityMetrics.annotationCompleteness * 100).toInt()}% covered',
                  color: AppTheme.accentEmerald,
                  icon: Icons.analytics_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            KeyValueRow(
              label: 'Genes detected',
              value: parseResult.qualityMetrics.genesCovered.isEmpty
                  ? 'None found'
                  : parseResult.qualityMetrics.genesCovered.join(', '),
            ),
            KeyValueRow(
              label: 'Variants',
              value: '${parseResult.qualityMetrics.variantsDetected}',
            ),
            if (parseResult.qualityMetrics.diplotypeInferred)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'One or more alleles defaulted to *1 (inferred).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.warningAmber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
