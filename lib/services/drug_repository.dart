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
      uses: ['Pain relief when prescribed'],
      commonSideEffects: ['Nausea', 'Constipation', 'Drowsiness'],
      seriousSideEffects: ['Slow or difficult breathing', 'Severe sedation'],
      precautions: ['Use only as prescribed; opioid risks apply'],
    ),
    DrugMetadata(
      genericName: 'CLOPIDOGREL',
      displayName: 'Clopidogrel',
      aliases: ['Plavix', 'Clopivas', 'Deplatt', 'Clopilet'],
      genes: ['CYP2C19'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC CYP2C19–clopidogrel guideline (2022)',
      ruleAvailable: true,
      uses: ['Prevention of blood clots in selected cardiovascular conditions'],
      commonSideEffects: ['Bruising', 'Nosebleeds', 'Diarrhea'],
      seriousSideEffects: ['Uncontrolled bleeding', 'Blood in stool or urine'],
      precautions: ['Review bleeding risk and all anticoagulant medicines'],
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
      uses: ['Prevention and treatment of blood clots'],
      commonSideEffects: ['Bruising', 'Minor bleeding'],
      seriousSideEffects: ['Heavy or unexplained bleeding', 'Severe headache'],
      precautions: ['INR monitoring and clinician-managed dosing are required'],
    ),
    DrugMetadata(
      genericName: 'SIMVASTATIN',
      displayName: 'Simvastatin',
      aliases: ['Zocor', 'Simvotin', 'Simcard'],
      genes: ['SLCO1B1'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC SLCO1B1–statin guideline (2022)',
      ruleAvailable: true,
      uses: ['Cholesterol reduction and cardiovascular risk reduction'],
      commonSideEffects: ['Muscle aches', 'Headache', 'Digestive upset'],
      seriousSideEffects: ['Severe muscle pain or weakness', 'Dark urine'],
      precautions: ['Report muscle symptoms and review interacting medicines'],
    ),
    DrugMetadata(
      genericName: 'AZATHIOPRINE',
      displayName: 'Azathioprine',
      aliases: ['Imuran', 'Azasan'],
      genes: ['TPMT'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC thiopurine guideline (2018)',
      ruleAvailable: true,
      uses: ['Immune-mediated conditions when prescribed by a specialist'],
      commonSideEffects: ['Nausea', 'Reduced appetite'],
      seriousSideEffects: ['Fever or infection', 'Unusual bleeding'],
      precautions: ['Blood-count monitoring is required'],
    ),
    DrugMetadata(
      genericName: 'FLUOROURACIL',
      displayName: 'Fluorouracil',
      aliases: ['5-FU', '5 FU', 'Adrucil', 'Capecitabine', 'Xeloda'],
      genes: ['DPYD'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC DPYD–fluoropyrimidine guideline (2018)',
      ruleAvailable: true,
      uses: ['Cancer treatment under oncology supervision'],
      commonSideEffects: ['Nausea', 'Diarrhea', 'Mouth sores'],
      seriousSideEffects: ['Severe diarrhea', 'Severe infection signs', 'Chest pain'],
      precautions: ['Oncology-supervised treatment and toxicity monitoring are required'],
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

    // The normalization dictionary is broader than the curated PGx panel.
    // A confidently recognized medicine is still verified even when no
    // drug-gene rule is available; the rule engine will perform clinical-only
    // checks and must not invent a PGx relationship.
    if (identity.verified && identity.genericName != 'UNKNOWN') {
      return DrugMetadata(
        genericName: identity.genericName,
        displayName: identity.displayName,
        aliases: identity.aliases,
        genes: const [],
        requiredClinicalData: const [],
        evidenceSource: 'Local medicine identity dictionary; no local PGx rule configured.',
        ruleAvailable: false,
      );
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
            uses: c.uses,
            commonSideEffects: c.commonSideEffects,
            seriousSideEffects: c.seriousSideEffects,
            precautions: c.precautions,
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
      verifiedMedicine: true,
      identityConfidence: 0.98,
      uses: metadata.uses,
      commonSideEffects: metadata.commonSideEffects,
      seriousSideEffects: metadata.seriousSideEffects,
      precautions: metadata.precautions,
    );
  }
}
