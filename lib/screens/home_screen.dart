import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/genomic_drug_scan_report.dart';
import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import 'chatbot_screen.dart';
import 'drug_input_screen.dart';
import 'genomic_scan_screen.dart';
import 'history_screen.dart';
import 'patient_profile_screen.dart';
import 'results_screen.dart';
import 'sign_in_screen.dart';
import 'upload_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await FirebaseService.signOut();
    ref.read(userProfileProvider.notifier).state = null;
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (_) => false,
      );
    }
  }

  void _openUpload(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen()));
  }

  void _openMedicine(BuildContext context, WidgetRef ref) {
    if (ref.read(vcfParseResultProvider) == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const UploadScreen(returnToMedicine: true, returnToDashboard: false),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrugInputScreen()));
  }

  void _openWatchlist(BuildContext context, WidgetRef ref, GenomicDrugScanReport? scan) {
    if (scan == null) {
      _openUpload(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenomicScanScreen(report: scan)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parseResult = ref.watch(vcfParseResultProvider);
    final scan = ref.watch(genomicScanReportProvider);
    final reportsAsync = ref.watch(userReportsStreamProvider);
    final latestReport = reportsAsync.valueOrNull?.isNotEmpty == true
        ? reportsAsync.valueOrNull!.first
        : null;
    final genes = parseResult?.geneProfiles.length ?? 0;
    final actionableGenes = parseResult?.geneProfiles.values
            .where((gene) => gene.phenotype != 'Unknown')
            .length ??
        0;
    final watchCount = scan?.actionableReports.length ?? 0;
    final displayName = ref.watch(userProfileProvider)?.displayName ??
        FirebaseService.currentUser?.displayName ??
        'there';

    return Scaffold(
      appBar: AppBar(
        title: const Text('OnCapRX'),
        actions: [
          IconButton(
            tooltip: 'Search medicine',
            icon: const Icon(Icons.search),
            onPressed: () => _openMedicine(context, ref),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PatientProfileScreen()));
              } else if (value == 'reports') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
              } else if (value == 'sign_out') {
                _signOut(context, ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('My profile')),
              PopupMenuItem(value: 'reports', child: Text('Reports')),
              PopupMenuItem(value: 'sign_out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(userReportsStreamProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _hero(context, displayName, parseResult != null, () => _openUpload(context)),
              const SizedBox(height: 18),
              if (parseResult == null)
                _emptyProfile(context, () => _openUpload(context))
              else ...[
                _summaryCard(context, genes, actionableGenes, () => _openProfile(context, parseResult)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _metricCard(context, 'Drugs to Watch', '$watchCount need attention', Icons.warning_amber_rounded, Colors.deepOrange, () => _openWatchlist(context, ref, scan)),
                    const SizedBox(width: 12),
                    _metricCard(context, 'Prescription Check', latestReport == null ? 'Not checked yet' : '${latestReport.drugReports.length} medicines', Icons.medication_outlined, Colors.indigo, () => latestReport == null ? _openMedicine(context, ref) : Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultsScreen(report: latestReport)))),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Quick actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _primaryAction(context, 'Check Prescription', 'Enter one or more medicines and analyze them.', Icons.medication, () => _openMedicine(context, ref)),
                const SizedBox(height: 10),
                _primaryAction(context, 'Drugs to Watch', 'Review medicines flagged by your genetic profile.', Icons.warning_amber, () => _openWatchlist(context, ref, scan)),
                const SizedBox(height: 18),
                _insightCard(context, genes, actionableGenes, () => _openProfile(context, parseResult)),
              ],
              const SizedBox(height: 18),
              _aiCard(context, latestReport, reportsAsync.valueOrNull ?? const <PgxMultiReport>[]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, String name, bool analyzed, VoidCallback upload) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF123B36),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hello, $name', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Know your genes. Understand your medicines.', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 18),
          InkWell(
            onTap: analyzed ? null : upload,
            child: Row(children: [
              Icon(analyzed ? Icons.check_circle : Icons.info_outline, color: analyzed ? Colors.greenAccent : Colors.amberAccent),
              const SizedBox(width: 8),
              Text(analyzed ? 'Genetic Profile: Analyzed' : 'Genetic Profile: Not analyzed', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (!analyzed) ...[const Spacer(), const Text('Analyze your VCF ->', style: TextStyle(color: Colors.amberAccent))],
            ]),
          ),
        ]),
      );

  Widget _emptyProfile(BuildContext context, VoidCallback upload) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            const Icon(Icons.biotech_outlined, size: 48, color: Colors.teal),
            const SizedBox(height: 10),
            const Text('Build your medication profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Upload a VCF file to identify genetic information relevant to medicines.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: upload, icon: const Icon(Icons.upload_file), label: const Text('Upload VCF')),
          ]),
        ),
      );

  Widget _summaryCard(BuildContext context, int genes, int actionable, VoidCallback onTap) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const Icon(Icons.biotech_outlined, size: 34, color: Colors.teal),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Genetic Profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('$genes genes analyzed  •  $actionable actionable findings'),
              ])),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );

  Widget _metricCard(BuildContext context, String title, String value, IconData icon, Color color, VoidCallback onTap) => Expanded(
        child: Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: color),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 12)),
                const Align(alignment: Alignment.centerRight, child: Icon(Icons.arrow_forward, size: 16)),
              ]),
            ),
          ),
        ),
      );

  Widget _primaryAction(BuildContext context, String title, String subtitle, IconData icon, VoidCallback onTap) => FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(subtitle, style: const TextStyle(fontSize: 12))])),
        style: FilledButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft),
      );

  Widget _insightCard(BuildContext context, int genes, int actionable, VoidCallback onTap) => Card(
        color: Colors.teal.shade50,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline, color: Colors.teal),
              const SizedBox(width: 12),
              Expanded(child: Text(actionable == 0 ? 'Your profile currently shows no major actionable pharmacogenomic findings.' : 'Your genetic profile may affect how some medicines are processed. $actionable finding(s) may need review.')),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );

  Widget _aiCard(BuildContext context, PgxMultiReport? latest, List<PgxMultiReport> reports) => Card(
        child: ListTile(
          leading: const Icon(Icons.smart_toy_outlined, color: Colors.teal),
          title: const Text('OnCapRX AI', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Ask about your verified medication results.'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatbotScreen(report: latest))),
        ),
      );

  void _openProfile(BuildContext context, dynamic parseResult) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GeneticProfileScreen(parseResult: parseResult)));
  }
}

class _GeneticProfileScreen extends StatelessWidget {
  final dynamic parseResult;
  const _GeneticProfileScreen({required this.parseResult});

  @override
  Widget build(BuildContext context) {
    final profiles = parseResult.geneProfiles.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Genetic Profile')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${profiles.length} genes analyzed', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...profiles.map((gene) => Card(child: ExpansionTile(title: Text(gene.gene), subtitle: Text(gene.phenotype == 'Unknown' ? 'No actionable finding' : 'Actionable finding'), children: [Padding(padding: const EdgeInsets.all(16), child: Text('Diplotype: ${gene.diplotype}\nVariants: ${gene.variants.map((variant) => variant.rsid).join(', ')}'))]))),
      ]),
    );
  }
}
