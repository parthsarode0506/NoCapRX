import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/uploaded_vcf_file.dart';
import '../parser/vcf_parser.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../services/genomic_drug_scan_service.dart';
import '../services/patient_profile_service.dart';
import '../services/screen_cache_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'drug_input_screen.dart';
import 'genomic_scan_screen.dart';
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
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initExistingFiles());
  }

  Future<void> _initExistingFiles() async {
    final currentFiles = ref.read(uploadedVcfFilesProvider);
    if (currentFiles.isNotEmpty) return;

    final user = FirebaseService.currentUser;
    if (user == null) return;

    final cached = await ScreenCacheService.getUserVcfFiles(user.uid);
    if (cached.isNotEmpty && mounted) {
      ref.read(uploadedVcfFilesProvider.notifier).state = cached;
      _recalculateMergedState(cached);
    }
  }

  Future<void> _pickVcfFile() async {
    setState(() {
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vcf'],
        allowMultiple: true,
      );

      if (files.isNotEmpty) {
        final existingFiles = List<UploadedVcfFile>.from(
          ref.read(uploadedVcfFilesProvider),
        );
        int addedCount = 0;

        for (final platformFile in files) {
          final name = platformFile.name;
          if (!name.toLowerCase().endsWith('.vcf')) {
            _setError('Skipped "$name": Invalid file extension. Select .vcf files.');
            continue;
          }

          final bytes = await platformFile.readAsBytes();
          if (bytes.length > 5 * 1024 * 1024) {
            _setError('Skipped "$name": File size exceeds 5MB limit.');
            continue;
          }

          final content = utf8.decode(bytes);
          if (content.trim().isEmpty) {
            _setError('Skipped "$name": File is empty.');
            continue;
          }

          // Parse and validate individual file
          final parseResult = VcfParser.parseVcfContent(content);
          final detectedGenes = parseResult.geneProfiles.entries
              .where((e) => !e.value.isInferred || e.value.variants.isNotEmpty)
              .map((e) => e.key)
              .toList();

          final entry = UploadedVcfFile(
            fileName: name,
            content: content,
            uploadedAt: DateTime.now(),
            geneCount: detectedGenes.isNotEmpty
                ? detectedGenes.length
                : parseResult.geneProfiles.length,
            genes: detectedGenes.isNotEmpty
                ? detectedGenes
                : parseResult.geneProfiles.keys.toList(),
          );

          // Replace if same filename, otherwise append
          final existingIdx =
              existingFiles.indexWhere((f) => f.fileName == name);
          if (existingIdx != -1) {
            existingFiles[existingIdx] = entry;
          } else {
            existingFiles.add(entry);
          }
          addedCount++;
        }

        if (addedCount > 0) {
          await _persistAndApplyFiles(existingFiles);
        }
      }
    } catch (e) {
      _setError('VCF Parsing Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _loadSampleVcf(String assetPath, String displayName) async {
    setState(() {
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final content = await rootBundle.loadString(assetPath);
      final parseResult = VcfParser.parseVcfContent(content);

      final detectedGenes = parseResult.geneProfiles.entries
          .where((e) => !e.value.isInferred || e.value.variants.isNotEmpty)
          .map((e) => e.key)
          .toList();

      final entry = UploadedVcfFile(
        fileName: displayName,
        content: content,
        uploadedAt: DateTime.now(),
        geneCount: detectedGenes.isNotEmpty
            ? detectedGenes.length
            : parseResult.geneProfiles.length,
        genes: detectedGenes.isNotEmpty
            ? detectedGenes
            : parseResult.geneProfiles.keys.toList(),
      );

      final existingFiles = List<UploadedVcfFile>.from(
        ref.read(uploadedVcfFilesProvider),
      );
      final existingIdx =
          existingFiles.indexWhere((f) => f.fileName == displayName);
      if (existingIdx != -1) {
        existingFiles[existingIdx] = entry;
      } else {
        existingFiles.add(entry);
      }

      await _persistAndApplyFiles(existingFiles);
    } catch (e) {
      _setError('Error loading sample VCF: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _removeFile(int index) async {
    final existingFiles = List<UploadedVcfFile>.from(
      ref.read(uploadedVcfFilesProvider),
    );
    if (index >= 0 && index < existingFiles.length) {
      existingFiles.removeAt(index);
      await _persistAndApplyFiles(existingFiles);
    }
  }

  Future<void> _clearAllFiles() async {
    await _persistAndApplyFiles([]);
  }

  Future<void> _persistAndApplyFiles(List<UploadedVcfFile> files) async {
    final uid = FirebaseService.currentUser?.uid ?? 'anonymous';
    await ScreenCacheService.saveUserVcfFiles(uid, files);
    ref.read(uploadedVcfFilesProvider.notifier).state = files;

    _recalculateMergedState(files);

    if (files.isNotEmpty) {
      final names = files.map((f) => f.fileName).join(', ');
      final merged = ref.read(vcfParseResultProvider);
      if (merged != null) {
        await _syncReportMetadata(names, merged);
      }

      // Update patient profile with loaded VCF filenames
      final currentProfile = ref.read(patientProfileProvider);
      if (currentProfile.hasData) {
        final updated = currentProfile.copyWith(vcfFilename: names);
        await PatientProfileService.save(updated);
        ref.read(patientProfileProvider.notifier).state = updated;
      }
    } else {
      final currentProfile = ref.read(patientProfileProvider);
      if (currentProfile.hasData) {
        final updated = currentProfile.copyWith(vcfFilename: null);
        await PatientProfileService.save(updated);
        ref.read(patientProfileProvider.notifier).state = updated;
      }
    }

    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  void _recalculateMergedState(List<UploadedVcfFile> files) {
    if (files.isEmpty) {
      ref.read(selectedVcfFilenameProvider.notifier).state = null;
      ref.read(selectedVcfContentProvider.notifier).state = null;
      ref.read(vcfParseResultProvider.notifier).state = null;
      ref.read(genomicScanReportProvider.notifier).state = null;
      return;
    }

    final parseResults = <VcfParseResult>[];
    for (final f in files) {
      try {
        final res = VcfParser.parseVcfContent(f.content);
        parseResults.add(res);
      } catch (_) {}
    }

    if (parseResults.isEmpty) return;

    final merged = VcfParser.mergeResults(parseResults);
    final names = files.map((f) => f.fileName).join(', ');

    ref.read(selectedVcfFilenameProvider.notifier).state = names;
    ref.read(selectedVcfContentProvider.notifier).state = files.last.content;
    ref.read(vcfParseResultProvider.notifier).state = merged;
    ref.read(genomicScanReportProvider.notifier).state =
        GenomicDrugScanService.scan(
      parseResult: merged,
      vcfFilename: names,
    );
  }

  Future<void> _syncReportMetadata(
    String name,
    VcfParseResult parseResult,
  ) async {
    // Always save VCF filename to local patient profile
    try {
      final currentProfile = ref.read(patientProfileProvider);
      if (currentProfile.vcfFilename != name) {
        final updated = currentProfile.copyWith(vcfFilename: name);
        await PatientProfileService.save(updated);
        if (mounted) ref.read(patientProfileProvider.notifier).state = updated;
      }
    } catch (_) {}

    if (FirebaseService.isCloudAvailable &&
        FirebaseService.currentUser != null) {
      final uid = FirebaseService.currentUser!.uid;
      final patientId = ref.read(patientProfileProvider).patientId;
      final reportId = 'REP_${DateTime.now().millisecondsSinceEpoch}';
      final profiles = parseResult.geneProfiles.values
          .map((gene) => <String, Object?>{
                'gene': gene.gene,
                'diplotype': gene.diplotype,
                'phenotype': gene.phenotype,
                'isInferred': gene.isInferred,
              })
          .toList(growable: false);

      try {
        final firestore = FirebaseFirestore.instance;
        await firestore.collection('geneticReports').doc(reportId).set({
          'reportId': reportId,
          'patientId': patientId,
          'ownerUid': uid,
          'storagePath': 'private_vcf/$uid/$name',
          'status': 'completed',
          'reportVersion': 1,
          'geneCount': parseResult.geneProfiles.length,
          'actionableCount': parseResult.geneProfiles.values
              .where((g) => g.phenotype != 'Unknown')
              .length,
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final summaryData = <String, Object?>{
          'vcfStatus': 'uploaded',
          'analysisStatus': 'complete',
          'vcfFileName': name,
          'vcfFilename': name,
          'sharedGenomicProfiles': profiles,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Update users/{uid} with both top-level summary and nested patientProfile.vcf_filename
        await firestore.collection('users').doc(uid).set({
          ...summaryData,
          'patientProfile': {
            'vcf_filename': name,
          },
        }, SetOptions(merge: true));

        await firestore.collection('patients').doc(uid).set(summaryData, SetOptions(merge: true));
        if (patientId.isNotEmpty) {
          await firestore.collection('patients').doc(patientId).set(summaryData, SetOptions(merge: true));
        }

        // Also update any organization directory request documents
        try {
          final userRequests = await firestore
              .collection('users')
              .doc(uid)
              .collection('directoryRequests')
              .get();
          for (final reqDoc in userRequests.docs) {
            final orgId = reqDoc.id;
            await firestore
                .collection('organizationDirectory')
                .doc(orgId)
                .collection('requests')
                .doc(uid)
                .set(summaryData, SetOptions(merge: true));
            // Also store with patientUid field for traceability
            final orgPatientData = {
              ...summaryData,
              'patientUid': uid,
              if (patientId.isNotEmpty) 'patientId': patientId,
              'name': ref.read(patientProfileProvider).fullName.isNotEmpty
                  ? ref.read(patientProfileProvider).fullName
                  : 'Patient',
            };
            await firestore
                .collection('organizationDirectory')
                .doc(orgId)
                .collection('patients')
                .doc(patientId.isNotEmpty ? patientId : uid)
                .set(orgPatientData, SetOptions(merge: true));
          }
        } catch (_) {}
      } catch (e) {
        debugPrint('_syncReportMetadata error: $e');
      }
    }
  }

  void _setError(String msg) {
    setState(() {
      _errorMessage = msg;
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DrugInputScreen()));
  }

  void _continueToDashboard() {
    if (widget.returnToMedicine) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DrugInputScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploadedFiles = ref.watch(uploadedVcfFilesProvider);
    final parseResult = ref.watch(vcfParseResultProvider);
    final hasFiles = uploadedFiles.isNotEmpty && parseResult != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Genetic VCF Data'),
        actions: [
          if (hasFiles)
            TextButton.icon(
              onPressed: _continueToDashboard,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Done'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntro(theme),
              const SizedBox(height: 20),
              _buildDropzone(theme, hasFiles),
              const SizedBox(height: 14),

              // Quick Sample Preset Selector
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.mintSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.vibrantMint.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.science_outlined,
                          size: 16,
                          color: AppTheme.primaryEmerald,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Try verified clinical sample profiles:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryEmerald,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(
                            Icons.add,
                            size: 14,
                            color: AppTheme.safeGreen,
                          ),
                          label: const Text('+ Normal (CYP2D6 *1/*1)'),
                          onPressed:
                              _isProcessing
                                  ? null
                                  : () => _loadSampleVcf(
                                    'assets/samples/patient_001_normal.vcf',
                                    'patient_001_normal.vcf',
                                  ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.add,
                            size: 14,
                            color: AppTheme.warningAmber,
                          ),
                          label: const Text('+ Intermediate (*1/*2)'),
                          onPressed:
                              _isProcessing
                                  ? null
                                  : () => _loadSampleVcf(
                                    'assets/samples/patient_002_reduced_function.vcf',
                                    'patient_002_reduced_function.vcf',
                                  ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.add,
                            size: 14,
                            color: AppTheme.dangerRed,
                          ),
                          label: const Text('+ High Risk (*2/*2)'),
                          onPressed:
                              _isProcessing
                                  ? null
                                  : () => _loadSampleVcf(
                                    'assets/samples/patient_003_high_risk.vcf',
                                    'patient_003_high_risk.vcf',
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                NoticeBanner(tone: NoticeTone.danger, message: _errorMessage!),
                const SizedBox(height: 16),
              ],

              // Show list of uploaded files
              if (hasFiles) ...[
                _buildFilesList(theme, uploadedFiles, parseResult),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _continueToDashboard,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Save & Open Dashboard'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _checkMedicine,
                  icon: const Icon(Icons.medication_outlined),
                  label: const Text('Check a Medicine with This Profile'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _scanAllDrugRisks,
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('Scan All Medicine Risks'),
                ),
                const SizedBox(height: 16),
              ],

              const NoticeBanner(
                tone: NoticeTone.info,
                title: 'On-device Privacy Guarantee',
                message:
                    'All your VCF files are saved and parsed on this device. '
                    'Raw genetic sequence data never leaves your device. '
                    'Only safe localized CPIC guidelines are computed locally.',
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
          child: const Icon(
            Icons.biotech_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upload Genetic VCF Files',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Upload one or multiple VCF files for different genes. '
                'All files are permanently saved to your patient profile.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDropzone(ThemeData theme, bool hasFiles) {
    final activeColor = hasFiles ? AppTheme.safeGreen : AppTheme.accentEmerald;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : _pickVcfFile,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: activeColor.withValues(alpha: 0.55),
              width: 1.6,
            ),
          ),
          child:
              _isProcessing
                  ? Column(
                    children: [
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 14),
                      Text('Reading and parsing VCF files…', style: theme.textTheme.titleMedium),
                    ],
                  )
                  : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasFiles
                              ? Icons.add_circle_outline_rounded
                              : Icons.upload_file_rounded,
                          size: 36,
                          color: activeColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasFiles
                            ? '+ Tap to Upload Another VCF File'
                            : 'Tap to Choose .vcf File(s)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color:
                              hasFiles
                                  ? AppTheme.primaryEmerald
                                  : AppTheme.deepInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select single or multiple VCF files (up to 5MB each)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildFilesList(
    ThemeData theme,
    List<UploadedVcfFile> files,
    VcfParseResult parseResult,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Uploaded VCF Files (${files.length}):',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.deepInk,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearAllFiles,
              icon: const Icon(Icons.delete_sweep, size: 16, color: AppTheme.dangerRed),
              label: const Text(
                'Remove All',
                style: TextStyle(color: AppTheme.dangerRed, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Cards for each uploaded file
        ...files.asMap().entries.map((entry) {
          final idx = entry.key;
          final file = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.biotech,
                    color: AppTheme.primaryEmerald,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.fileName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 4,
                        children: [
                          if (file.genes.isNotEmpty)
                            ...file.genes.map(
                              (g) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.mintSurface,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  g,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryEmerald,
                                  ),
                                ),
                              ),
                            )
                          else
                            Text(
                              '${file.geneCount} genes detected',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.dangerRed,
                    size: 20,
                  ),
                  onPressed: () => _removeFile(idx),
                  tooltip: 'Remove ${file.fileName}',
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 12),
        // Unified Merged Genomic Summary Card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.stacked_bar_chart,
                    color: AppTheme.primaryEmerald,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Combined Pharmacogene Coverage',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PillBadge(
                    label: '${parseResult.geneProfiles.length} Genes',
                    color: AppTheme.accentEmerald,
                    icon: Icons.analytics_outlined,
                  ),
                ],
              ),
              const Divider(height: 18),
              KeyValueRow(
                label: 'Covered Genes',
                value:
                    parseResult.qualityMetrics.genesCovered.isEmpty
                        ? parseResult.geneProfiles.keys.join(', ')
                        : parseResult.qualityMetrics.genesCovered.join(', '),
              ),
              KeyValueRow(
                label: 'Total Variants Detected',
                value: '${parseResult.qualityMetrics.variantsDetected}',
              ),
              KeyValueRow(
                label: 'Active Medication Warnings',
                value:
                    '${parseResult.geneProfiles.values.where((g) => g.phenotype != 'Unknown').length} actionable genes',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
