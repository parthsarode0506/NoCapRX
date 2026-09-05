import '../models/drug_metadata.dart';

/// The immutable, offline medicine/evidence index.
///
/// A remote evidence service may add candidates only after server-side
/// validation. It must not mutate this local clinical rule panel on-device.
class DrugRepository {
  static const List<DrugMetadata> _drugs = [
    DrugMetadata(
      genericName: 'CODEINE',
      displayName: 'Codeine',
      aliases: ['Codeine Phosphate', 'Tylenol #3'],
      genes: ['CYP2D6'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC CYP2D6–opioids guideline',
    ),
    DrugMetadata(
      genericName: 'CLOPIDOGREL',
      displayName: 'Clopidogrel',
      aliases: ['Plavix', 'Clopivas', 'Deplatt'],
      genes: ['CYP2C19'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC CYP2C19–clopidogrel guideline',
    ),
    DrugMetadata(
      genericName: 'WARFARIN',
      displayName: 'Warfarin',
      aliases: ['Coumadin', 'Jantoven'],
      genes: ['CYP2C9', 'VKORC1'],
      requiredClinicalData: [
        'Age',
        'Weight',
        'Height',
        'Indication',
        'Current INR',
        'Concurrent medicines',
      ],
      evidenceSource: 'CPIC warfarin dosing guideline',
    ),
    DrugMetadata(
      genericName: 'SIMVASTATIN',
      displayName: 'Simvastatin',
      aliases: ['Zocor', 'Simvotin'],
      genes: ['SLCO1B1'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC SLCO1B1–statin guideline',
    ),
    DrugMetadata(
      genericName: 'AZATHIOPRINE',
      displayName: 'Azathioprine',
      aliases: ['Imuran', 'Azasan'],
      genes: ['TPMT'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC thiopurine guideline',
    ),
    DrugMetadata(
      genericName: 'FLUOROURACIL',
      displayName: 'Fluorouracil',
      aliases: ['5-FU', 'Adrucil', 'Capecitabine', 'Xeloda'],
      genes: ['DPYD'],
      requiredClinicalData: [],
      evidenceSource: 'CPIC DPYD–fluoropyrimidine guideline',
    ),
    DrugMetadata(
      genericName: 'AZITHROMYCIN',
      displayName: 'Azithromycin',
      aliases: ['Azee 500', 'Azee', 'Zithromax', 'Azithral'],
      genes: [],
      requiredClinicalData: [],
      evidenceSource:
          'No validated deterministic PGx rule is included in this on-device panel.',
      ruleAvailable: false,
    ),
  ];

  static List<DrugMetadata> search(String query) {
    final term = query.trim().toUpperCase();
    if (term.isEmpty) return _drugs;
    return _drugs.where((drug) {
      return drug.genericName.contains(term) ||
          drug.displayName.toUpperCase().contains(term) ||
          drug.aliases.any((alias) => alias.toUpperCase().contains(term));
    }).toList();
  }

  static DrugMetadata? resolve(String query) {
    for (final drug in _drugs) {
      if (drug.matches(query)) return drug;
    }
    return null;
  }
}
