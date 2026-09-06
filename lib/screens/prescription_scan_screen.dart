import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../services/prescription_ocr_service.dart';
import '../services/drug_repository.dart';
import '../theme/app_theme.dart';

/// Result returned to the caller: the list of confirmed medicine names.
class PrescriptionScanResult {
  final List<String> medicines;
  final String rawOcrText;

  const PrescriptionScanResult({
    required this.medicines,
    required this.rawOcrText,
  });
}

/// Full-screen OCR prescription scanner.
///
/// Usage:
/// ```dart
/// final result = await Navigator.of(context)
///     .push(MaterialPageRoute(builder: (_) => const PrescriptionScanScreen()));
/// if (result != null) { /* use result.medicines */ }
/// ```
class PrescriptionScanScreen extends ConsumerStatefulWidget {
  const PrescriptionScanScreen({super.key});

  @override
  ConsumerState<PrescriptionScanScreen> createState() =>
      _PrescriptionScanScreenState();
}

class _PrescriptionScanScreenState
    extends ConsumerState<PrescriptionScanScreen> {
  // ─── State ────────────────────────────────────────────────────────────────
  _ScanPhase _phase = _ScanPhase.idle;
  String? _imagePath;
  String? _rawText;
  String? _errorMessage;

  /// Confirmed medicine names the user has accepted.
  List<String> _confirmedMedicines = [];

  /// Editable text in the "verify" step.
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  // ─── Image source selection ───────────────────────────────────────────────

  Future<void> _pickFromCamera() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image != null) await _processImage(image.path);
    } catch (e) {
      _setError('Camera unavailable: ${e.toString()}');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.image,
      );
      if (result != null && result.path != null) {
        await _processImage(result.path!);
      }
    } catch (e) {
      _setError('Gallery unavailable: ${e.toString()}');
    }
  }

  // ─── OCR pipeline ─────────────────────────────────────────────────────────

  Future<void> _processImage(String path) async {
    setState(() {
      _imagePath = path;
      _phase = _ScanPhase.scanning;
      _errorMessage = null;
      _rawText = null;
    });

    try {
      final text = await PrescriptionOcrService.extractText(path);

      if (text.trim().isEmpty) {
        _setError(
          'No text was detected in the image. '
          'Try taking a clearer, well-lit photo of the prescription.',
        );
        return;
      }

      final candidates = _extractMedicineCandidates(text);
      _editController.text = candidates.join(', ');

      setState(() {
        _rawText = text;
        _confirmedMedicines = List.from(candidates);
        _phase = _ScanPhase.verifying;
      });
    } catch (e) {
      _setError(
        'OCR processing failed. Ensure Google ML Kit is available on this device.\n'
        'Details: ${e.toString()}',
      );
    }
  }

  // ─── Medicine candidate extraction ───────────────────────────────────────

  List<String> _extractMedicineCandidates(String text) {
    final found = <String>{};

    // Split by common prescription line delimiters
    final phrases = text
        .split(RegExp(r'[\r\n,;:\.]+'))
        .map((line) => line
            .replaceAll(
                RegExp(r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|%|tab|tabs|cap|caps|ml)\b',
                    caseSensitive: false),
                '')
            .trim())
        .where((line) => line.length > 2);

    for (final phrase in phrases) {
      // Try full phrase
      final meta = DrugRepository.resolve(phrase);
      if (meta != null) {
        found.add(meta.displayName);
        continue;
      }

      // Try sliding window of 1–4 words
      final words =
          phrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      outer:
      for (var len = 4; len >= 1; len--) {
        for (var start = 0; start + len <= words.length; start++) {
          final candidate = words.sublist(start, start + len).join(' ');
          final match = DrugRepository.resolve(candidate);
          if (match != null) {
            found.add(match.displayName);
            break outer;
          }
        }
      }
    }

    return found.toList();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _setError(String msg) {
    setState(() {
      _phase = _ScanPhase.error;
      _errorMessage = msg;
    });
  }

  void _reset() {
    setState(() {
      _phase = _ScanPhase.idle;
      _imagePath = null;
      _rawText = null;
      _errorMessage = null;
      _confirmedMedicines = [];
      _editController.clear();
    });
  }

  void _confirmAndReturn() {
    // Parse the edited text field for the final list
    final edited = _editController.text
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (edited.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No medicines entered. Add at least one medicine.'),
          backgroundColor: AppTheme.warningAmber,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      PrescriptionScanResult(
        medicines: edited,
        rawOcrText: _rawText ?? '',
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scan Prescription',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.deepInk,
              ),
            ),
            Text(
              'AI extracts medicines • You verify',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.secondaryInk,
              ),
            ),
          ],
        ),
        actions: [
          if (_phase != _ScanPhase.idle)
            TextButton(
              onPressed: _reset,
              child: const Text('Rescan'),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _ScanPhase.idle:
        return _buildIdleView();
      case _ScanPhase.scanning:
        return _buildScanningView();
      case _ScanPhase.verifying:
        return _buildVerifyView();
      case _ScanPhase.error:
        return _buildErrorView();
    }
  }

  // ─── Phase: Idle (source selection) ──────────────────────────────────────

  Widget _buildIdleView() {
    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero illustration card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryDarkEmerald,
                  AppTheme.accentEmerald.withValues(alpha: 0.9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Prescription OCR Scanner',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Take a photo or upload an image of any prescription. '
                  'OCR reads the text and identifies medicines automatically.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Privacy badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 13, color: AppTheme.vibrantMint),
                      const SizedBox(width: 6),
                      Text(
                        'Cloud OCR when configured · ML Kit fallback offline',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Choose image source',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.deepInk,
            ),
          ),
          const SizedBox(height: 14),

          // Camera button
          _SourceButton(
            icon: Icons.camera_alt_rounded,
            title: 'Take a Photo',
            subtitle: 'Use your camera to photograph the prescription',
            color: AppTheme.primaryEmerald,
            onTap: _pickFromCamera,
          ),
          const SizedBox(height: 12),

          // Gallery/file button
          _SourceButton(
            icon: Icons.photo_library_rounded,
            title: 'Upload from Gallery',
            subtitle: 'Pick an existing photo from your device',
            color: AppTheme.accentEmerald,
            onTap: _pickFromGallery,
          ),

          const SizedBox(height: 28),

          // How-it-works steps
          _buildHowItWorksCard(),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppTheme.deepInk,
            ),
          ),
          const SizedBox(height: 12),
          _howStep('1', Icons.camera_alt_outlined, 'Photograph or upload the prescription'),
          _howStep('2', Icons.document_scanner_outlined, 'OCR reads all text (OpenRouter or Google ML Kit)'),
          _howStep('3', Icons.medication_outlined, 'Medicines are automatically identified'),
          _howStep('4', Icons.check_circle_outline, 'You review and confirm the list'),
          _howStep('5', Icons.biotech_outlined, 'PharmaGuard analyzes your genetics vs each medicine'),
        ],
      ),
    );
  }

  Widget _howStep(String num, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryEmerald,
              shape: BoxShape.circle,
            ),
            child: Text(
              num,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: AppTheme.accentEmerald),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: AppTheme.secondaryInk),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Phase: Scanning ─────────────────────────────────────────────────────

  Widget _buildScanningView() {
    return Center(
      key: const ValueKey('scanning'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(_imagePath!),
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 28),
            const CircularProgressIndicator(
              color: AppTheme.primaryEmerald,
              strokeWidth: 3,
            ),
            const SizedBox(height: 20),
            Text(
              'Reading prescription text…',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.deepInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'OCR is processing the image.\nYour image is sent to OpenRouter only when configured.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.secondaryInk,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.mintSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 14, color: AppTheme.primaryEmerald),
                  const SizedBox(width: 6),
                  Text(
                    'OCR processing in progress',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.primaryDarkEmerald,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Phase: Verify ────────────────────────────────────────────────────────

  Widget _buildVerifyView() {
    return SingleChildScrollView(
      key: const ValueKey('verifying'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.mintSurface,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppTheme.accentEmerald.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.primaryEmerald, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prescription text read successfully',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.primaryDarkEmerald,
                        ),
                      ),
                      Text(
                        '${_confirmedMedicines.length} medicine(s) identified',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppTheme.secondaryInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Image thumbnail
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_imagePath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Raw OCR text (expandable)
          if (_rawText != null && _rawText!.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.text_snippet_outlined,
                  color: AppTheme.accentEmerald),
              title: Text(
                'Raw OCR text (tap to view)',
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppTheme.secondaryInk),
              ),
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: SelectableText(
                    _rawText!,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 11.5,
                      color: AppTheme.deepInk,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // Edit field
          Text(
            'Confirm medicines to analyse',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.deepInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Edit the list below. Separate medicines with commas. '
            'Remove any that were mis-identified.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.secondaryInk,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _editController,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.deepInk,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Clopidogrel, Warfarin, Codeine',
              hintStyle: GoogleFonts.inter(
                  fontSize: 13, color: AppTheme.mutedGrey),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppTheme.primaryEmerald, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Identified chips
          if (_confirmedMedicines.isNotEmpty) ...[
            Text(
              'Auto-identified',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.secondaryInk,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _confirmedMedicines
                  .map(
                    (m) => Chip(
                      label: Text(
                        m,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryDarkEmerald,
                        ),
                      ),
                      backgroundColor: AppTheme.mintSurface,
                      side: BorderSide(
                          color:
                              AppTheme.accentEmerald.withValues(alpha: 0.35)),
                      avatar: const Icon(
                        Icons.medication_outlined,
                        size: 14,
                        color: AppTheme.primaryEmerald,
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        setState(() {
                          _confirmedMedicines.remove(m);
                          // Sync edit field
                          _editController.text =
                              _confirmedMedicines.join(', ');
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // No medicines warning
          if (_confirmedMedicines.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No recognised medicines were auto-identified. '
                      'Type the medicine names manually in the field above.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          // CTA buttons
          FilledButton.icon(
            onPressed: _confirmAndReturn,
            icon: const Icon(Icons.biotech_outlined),
            label: const Text('Analyse These Medicines'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryEmerald,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Rescan Prescription'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Phase: Error ─────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
            ),
            const SizedBox(height: 20),
            Text(
              'Scan failed',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.deepInk,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ?? 'An unknown error occurred.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.secondaryInk,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                minimumSize: const Size(200, 48),
              ),
            ),
            const SizedBox(height: 12),
            // Manual entry fallback
            OutlinedButton.icon(
              onPressed: () {
                // Return empty result so caller shows manual entry
                Navigator.of(context).pop(
                  const PrescriptionScanResult(medicines: [], rawOcrText: ''),
                );
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Enter Medicine Manually'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(200, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Supporting widgets ────────────────────────────────────────────────────

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.secondaryInk,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppTheme.mutedGrey),
          ],
        ),
      ),
    );
  }
}

// ─── Phase enum ───────────────────────────────────────────────────────────

enum _ScanPhase { idle, scanning, verifying, error }
