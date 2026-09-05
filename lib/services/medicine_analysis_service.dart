import '../services/drug_repository.dart';
import '../services/local_discovery_cache.dart';
import '../services/patient_profile_service.dart';

/// Owns readiness for all dependencies used by medicine analysis.
/// The deterministic rule engine remains stateless and authoritative.
class MedicineAnalysisService {
  MedicineAnalysisService._();

  static final MedicineAnalysisService instance = MedicineAnalysisService._();
  Future<void>? _initialization;
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> initialize() {
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    await LocalDiscoveryCache.init();
    // Touch the local repository after its cache is loaded so all later
    // resolution calls observe the same initialized catalogue.
    DrugRepository.search('');
    await PatientProfileService.load();
    _ready = true;
  }

  Future<void> ensureReady() async {
    await initialize();
    if (!_ready) {
      throw StateError('Medicine analysis services failed to initialize.');
    }
  }
}
