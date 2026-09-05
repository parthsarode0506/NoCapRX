import '../models/drug_evidence.dart';
import '../models/drug_metadata.dart';
import 'local_discovery_cache.dart';
import 'medicine_normalization_service.dart';

/// The offline-first medicine catalogue and repository.
/// Seamlessly blends pre-bundled core clinical panels with persistent
/// online-discovered drug evidence cached on-device.
class DrugRepository {
  static const List<DrugMetadata> _prebundledDrugs = [
    DrugMetadata(
      genericName: 'CODEINE',
      displayName: 'Codeine',
      aliases: ['Codeine Phosphate', 'Tylenol #3', 'Tylenol 3'],
      genes: ['CYP2D6'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC CYP2D6–opioids guideline (2021)',
      ruleAvailable: true,
    ),
    DrugMetadata(
      genericName: 'CLOPIDOGREL',
      displayName: 'Clopidogrel',
      aliases: ['Plavix', 'Clopivas', 'Deplatt', 'Clopilet'],
      genes: ['CYP2C19'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC CYP2C19–clopidogrel guideline (2022)',
      ruleAvailable: true,
    ),
    DrugMetadata(
      genericName: 'WARFARIN',
      displayName: 'Warfarin',
      aliases: ['Coumadin', 'Jantoven', 'Warf'],
      genes: ['CYP2C9', 'VKORC1'],
      requiredClinicalData: [
        'Age',
        'Weight',
        'Height',
        'Indication',
        'Current INR',
        'Concurrent medicines',
      ],
      evidenceSource: 'CPIC warfarin dosing guideline (2017)',
      ruleAvailable: true,
    ),
    DrugMetadata(
      genericName: 'SIMVASTATIN',
      displayName: 'Simvastatin',
      aliases: ['Zocor', 'Simvotin', 'Simcard'],
      genes: ['SLCO1B1'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC SLCO1B1–statin guideline (2022)',
      ruleAvailable: true,
    ),
    DrugMetadata(
      genericName: 'AZATHIOPRINE',
      displayName: 'Azathioprine',
      aliases: ['Imuran', 'Azasan'],
      genes: ['TPMT'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC thiopurine guideline (2018)',
      ruleAvailable: true,
    ),
    DrugMetadata(
      genericName: 'FLUOROURACIL',
      displayName: 'Fluorouracil',
      aliases: ['5-FU', '5 FU', 'Adrucil', 'Capecitabine', 'Xeloda'],
      genes: ['DPYD'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC DPYD–fluoropyrimidine guideline (2018)',
      ruleAvailable: true,
    ),
    DrugMetadata(
      genericName: 'AZITHROMYCIN',
      displayName: 'Azithromycin',
      aliases: ['Azee 500', 'Azee', 'Zithromax', 'Azithral', 'Z-Pak'],
      genes: [],
      requiredClinicalData: [],
      evidenceSource:
          'No clinically actionable pharmacogenomic relationship found in CPIC guidelines.',
      ruleAvailable: false,
    ),
    DrugMetadata(
      genericName: 'PARACETAMOL',
      displayName: 'Paracetamol / Acetaminophen',
      aliases: ['Acetaminophen', 'Tylenol', 'Crocin', 'Calpol', 'Panadol', 'Dolo 650'],
      genes: [],
      requiredClinicalData: [],
      evidenceSource:
          'No clinically actionable germline pharmacogenomic prescribing guideline.',
      ruleAvailable: false,
    ),
  ];

  /// Searches all pre-bundled drugs and cached online discoveries.
  static List<DrugMetadata> search(String query) {
    final term = MedicineNormalizationService.cleanQuery(query);
    final allDrugs = _getAllKnownDrugs();
    if (term.isEmpty) return allDrugs;

    return allDrugs.where((drug) {
      return drug.genericName.contains(term) ||
          drug.displayName.toUpperCase().contains(term) ||
          drug.aliases.any((alias) =>
              alias.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').contains(
                  term.replaceAll(RegExp(r'[^A-Z0-9]'), '')));
    }).toList();
  }

  /// Resolves an exact or alias match for a drug query.
  static DrugMetadata? resolve(String query) {
    final identity = MedicineNormalizationService.identify(query);
    final allDrugs = _getAllKnownDrugs();

    for (final drug in allDrugs) {
      if (drug.genericName == identity.genericName ||
          drug.displayName.toUpperCase() == identity.displayName.toUpperCase() ||
          drug.matches(query) ||
          drug.matches(identity.genericName)) {
        return drug;
      }
    }
    return null;
  }

  /// Checks if a drug is locally available (prebundled or cached).
  static bool isLocallyAvailable(String drugName) {
    return resolve(drugName) != null;
  }

  static List<DrugMetadata> _getAllKnownDrugs() {
    final list = List<DrugMetadata>.from(_prebundledDrugs);
    final cached = LocalDiscoveryCache.getAllCached();

    for (final c in cached) {
      if (!list.any((d) => d.genericName == c.genericName)) {
        list.add(
          DrugMetadata(
            genericName: c.genericName,
            displayName: c.displayName,
            aliases: c.aliases,
            genes: c.genes,
            requiredClinicalData: c.requiredClinicalData,
            evidenceSource: '${c.source} (${c.evidenceLevel})',
            ruleAvailable: c.hasPgxRelationship && c.genes.isNotEmpty,
          ),
        );
      }
    }
    return list;
  }

  /// Converts DrugMetadata to DrugEvidence.
  static DrugEvidence toDrugEvidence(DrugMetadata metadata) {
    return DrugEvidence(
      genericName: metadata.genericName,
      displayName: metadata.displayName,
      aliases: metadata.aliases,
      genes: metadata.genes,
      guidelineCitation: metadata.evidenceSource,
      evidenceLevel: 'Validated Local Panel',
      source: 'CPIC Guidelines',
      hasPgxRelationship: metadata.genes.isNotEmpty,
      clinicallyActionable: metadata.ruleAvailable,
      requiredClinicalData: metadata.requiredClinicalData,
      retrievalTimestamp: DateTime.now().toIso8601String(),
    );
  }
}
