import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../models/pgx_report.dart';
import '../models/patient_profile.dart';
import '../parser/vcf_parser.dart';
import '../services/firebase_service.dart';

// Firebase Auth State Stream
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseService.authStateChanges;
});

// Current User Profile State
final userProfileProvider = StateProvider<AppUser?>((ref) => null);
final patientProfileProvider = StateProvider<PatientProfile>((ref) => const PatientProfile());

// Picked VCF data is retained in memory so the same flow works in browsers,
// where the selected file does not have a filesystem path.
final selectedVcfFilenameProvider = StateProvider<String?>((ref) => null);
final selectedVcfContentProvider = StateProvider<String?>((ref) => null);

// VCF Parsing Result State
final vcfParseResultProvider = StateProvider<VcfParseResult?>((ref) => null);

// Drugs are opt-in. A patient should never receive a noisy six-drug report
// merely because they opened the medicine screen.
final selectedDrugsProvider = StateProvider<Set<String>>((ref) => <String>{});
final customDrugTextProvider = StateProvider<String>((ref) => '');

// Current Active Analysis Multi-Report
final currentReportProvider = StateProvider<PgxMultiReport?>((ref) => null);

// User Reports History Stream
final userReportsStreamProvider = StreamProvider<List<PgxMultiReport>>((ref) {
  ref.watch(authStateProvider);
  return FirebaseService.streamUserReports();
});

// View Toggle: Patient-friendly vs Clinician note
final isClinicianViewProvider = StateProvider<bool>((ref) => false);

// UI Theme Mode State
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
