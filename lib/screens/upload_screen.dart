import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_providers.dart';
import '../parser/vcf_parser.dart';
import '../theme/app_theme.dart';
import '../widgets/security_cards.dart';
import 'drug_input_screen.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

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

        setState(() {
          _isValid = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      _setError('VCF Parsing Error: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _loadSampleVcf(String assetPath, String sampleName) async {
    setState(() {
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final content = await rootBundle.loadString(assetPath);

      if (sampleName.contains('malformed')) {
        VcfParser.parseVcfContent(content);
      }

      final parseResult = VcfParser.parseVcfContent(content);

      ref.read(selectedVcfFilenameProvider.notifier).state = sampleName;
      ref.read(selectedVcfContentProvider.notifier).state = content;
      ref.read(vcfParseResultProvider.notifier).state = parseResult;

      setState(() {
        _isValid = true;
        _errorMessage = null;
      });
    } catch (e) {
      _setError('Sample Error ($sampleName): ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final filename = ref.watch(selectedVcfFilenameProvider);
    final parseResult = ref.watch(vcfParseResultProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Text(
          'Upload Genetic Data',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppTheme.deepInk,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step 1 Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.lightEmeraldPill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'STEP 1 OF 2',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryDarkEmerald,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select Patient VCF File',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppTheme.deepInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PharmaGuard processes genetic data 100% on your device. Raw VCF lines are never uploaded.',
                style: GoogleFonts.inter(
                  color: AppTheme.secondaryInk,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),

              // File Picker Dropzone Area
              InkWell(
                onTap: _isProcessing ? null : _pickVcfFile,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  decoration: BoxDecoration(
                    color: _isValid ? AppTheme.mintSurface : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isValid
                          ? AppTheme.safeGreen
                          : AppTheme.accentEmerald.withValues(alpha: 0.4),
                      width: _isValid ? 1.5 : 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isValid
                              ? AppTheme.safeGreen.withValues(alpha: 0.15)
                              : AppTheme.lightEmeraldPill,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isValid
                              ? Icons.check_circle_rounded
                              : Icons.cloud_upload_outlined,
                          size: 40,
                          color: _isValid ? AppTheme.safeGreen : AppTheme.primaryEmerald,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _isValid ? 'VCF File Loaded & Validated' : 'Tap to Browse .VCF File',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _isValid ? AppTheme.safeGreen : AppTheme.deepInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Supports VCF v4.2 format (Max size: 5MB)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.secondaryInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Error Display Box
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRedBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.dangerRed.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppTheme.dangerRed, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(
                            color: AppTheme.dangerRed,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // File Info Card when selected
              if (_isValid && filename != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.lightEmeraldPill,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.insert_drive_file_outlined,
                                    color: AppTheme.primaryEmerald,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    filename,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: AppTheme.deepInk,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppTheme.dangerRed),
                            onPressed: _removeFile,
                            tooltip: 'Remove File',
                          ),
                        ],
                      ),
                      if (parseResult != null) ...[
                        const Divider(height: 20),
                        Text(
                          'Parsing Quality Summary:',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppTheme.deepInk,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildQualityRow(
                          'Target Genes Detected',
                          parseResult.qualityMetrics.genesCovered.join(', '),
                        ),
                        _buildQualityRow(
                          'Total Variants',
                          '${parseResult.qualityMetrics.variantsDetected}',
                        ),
                        _buildQualityRow(
                          'Annotation Completeness',
                          '${(parseResult.qualityMetrics.annotationCompleteness * 100).toInt()}%',
                        ),
                        if (parseResult.qualityMetrics.diplotypeInferred)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '• Alleles defaulted to *1 (Inferred Reference)',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppTheme.warningAmber,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Quick Sample Files for Testing Section
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demo Test Samples:',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.deepInk,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          backgroundColor: AppTheme.mintSurface,
                          side: const BorderSide(color: AppTheme.cardBorder),
                          avatar: const Icon(Icons.check_circle_outline,
                              size: 16, color: AppTheme.safeGreen),
                          label: Text(
                            'Clean Sample',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          onPressed: () => _loadSampleVcf(
                            'assets/samples/sample_clean.vcf',
                            'sample_clean.vcf',
                          ),
                        ),
                        ActionChip(
                          backgroundColor: AppTheme.subtleFill,
                          side: const BorderSide(color: AppTheme.cardBorder),
                          avatar: const Icon(Icons.warning_amber_rounded,
                              size: 16, color: AppTheme.warningAmber),
                          label: Text(
                            'Missing INFO',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          onPressed: () => _loadSampleVcf(
                            'assets/samples/sample_missing_info.vcf',
                            'sample_missing_info.vcf',
                          ),
                        ),
                        ActionChip(
                          backgroundColor: AppTheme.subtleFill,
                          side: const BorderSide(color: AppTheme.cardBorder),
                          avatar: const Icon(Icons.error_outline_rounded,
                              size: 16, color: AppTheme.dangerRed),
                          label: Text(
                            'Malformed',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          onPressed: () => _loadSampleVcf(
                            'assets/samples/sample_malformed.vcf',
                            'sample_malformed.vcf',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // On-Device Privacy Micro-card
              const OnDevicePrivacyMicroCard(),
              const SizedBox(height: 24),

              // Next Button: Next: Select Drugs →
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isValid
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DrugInputScreen()),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Next: Select Medications',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.secondaryInk),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.deepInk,
            ),
          ),
        ],
      ),
    );
  }
}
