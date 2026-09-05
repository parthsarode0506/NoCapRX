import '../models/drug_evidence.dart';
import '../models/pgx_report.dart';
import '../parser/vcf_parser.dart';
import '../services/universal_medicine_safety_engine.dart';

class CpicRule {
  final String gene;
  final String drug;
  final String phenotype;
  final String riskLabel; // Safe, Adjust Dosage, Toxic, Ineffective, Unknown
  final String severity; // none, low, moderate, high, critical
  final double baseConfidence;
  final String mechanism;
  final String cpicGuidelineCitation;
  final String dosingRecommendation;
  final List<String> alternativeDrugs;
  final String monitoringAdvice;

  const CpicRule({
    required this.gene,
    required this.drug,
    required this.phenotype,
    required this.riskLabel,
    required this.severity,
    required this.baseConfidence,
    required this.mechanism,
    required this.cpicGuidelineCitation,
    required this.dosingRecommendation,
    required this.alternativeDrugs,
    required this.monitoringAdvice,
  });
}

class CpicRuleEngine {
  static const Map<String, String> drugToGeneMap = {
    // Local Core Panel (6 drugs)
    'CODEINE': 'CYP2D6',
    'CLOPIDOGREL': 'CYP2C19',
    'WARFARIN': 'CYP2C9',
    'SIMVASTATIN': 'SLCO1B1',
    'AZATHIOPRINE': 'TPMT',
    'FLUOROURACIL': 'DPYD',
    // Extended Online / Curated CPIC Panel
    'TACROLIMUS': 'CYP3A5',
    'ABACAVIR': 'HLA-B',
    'CARBAMAZEPINE': 'HLA-B',
    'PHENYTOIN': 'CYP2C9',
    'TAMOXIFEN': 'CYP2D6',
    'ONDANSETRON': 'CYP2D6',
    'IRINOTECAN': 'UGT1A1',
    'CELECOXIB': 'CYP2C9',
    'IBUPROFEN': 'CYP2C9',
    'AMITRIPTYLINE': 'CYP2D6',
  };

  /// Common generic, brand, and spelling variants.
  static const Map<String, String> _drugAliases = {
    'CODEINE PHOSPHATE': 'CODEINE',
    'TYLENOL 3': 'CODEINE',
    'TYLENOL #3': 'CODEINE',
    'PLAVIX': 'CLOPIDOGREL',
    'CLOPIVAS': 'CLOPIDOGREL',
    'DEPLATT': 'CLOPIDOGREL',
    'COUMADIN': 'WARFARIN',
    'JANTOVEN': 'WARFARIN',
    'WARF': 'WARFARIN',
    'ZOCOR': 'SIMVASTATIN',
    'SIMVOTIN': 'SIMVASTATIN',
    'IMURAN': 'AZATHIOPRINE',
    'AZASAN': 'AZATHIOPRINE',
    '5 FU': 'FLUOROURACIL',
    '5-FU': 'FLUOROURACIL',
    'ADRUCIL': 'FLUOROURACIL',
    'CAPECITABINE': 'FLUOROURACIL',
    'XELODA': 'FLUOROURACIL',
    'PROGRAF': 'TACROLIMUS',
    'ENVARSUS': 'TACROLIMUS',
    'ZIAGEN': 'ABACAVIR',
    'TRIUMEQ': 'ABACAVIR',
    'TEGRETOL': 'CARBAMAZEPINE',
    'CARBATROL': 'CARBAMAZEPINE',
    'DILANTIN': 'PHENYTOIN',
    'EPANUTIN': 'PHENYTOIN',
    'NOLVADEX': 'TAMOXIFEN',
    'SOLTAMOX': 'TAMOXIFEN',
    'ZOFRAN': 'ONDANSETRON',
    'ZUPLENZ': 'ONDANSETRON',
    'CAMPTOSAR': 'IRINOTECAN',
    'CELEBREX': 'CELECOXIB',
    'ADVIL': 'IBUPROFEN',
    'MOTRIN': 'IBUPROFEN',
    'ELAVIL': 'AMITRIPTYLINE',
  };

  /// Resolves a user-entered drug to a canonical rule name.
  static String? resolveDrugName(String drugName) {
    final normalized = drugName
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (drugToGeneMap.containsKey(normalized)) return normalized;
    return _drugAliases[normalized];
  }

  static final List<CpicRule> _rules = [
    // --- CYP2D6 : CODEINE ---
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'CODEINE',
      phenotype: 'PM',
      riskLabel: 'Ineffective',
      severity: 'high',
      baseConfidence: 0.95,
      mechanism: 'CYP2D6 enzyme activity is absent, preventing bioactivation of codeine into active morphine.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Codeine Therapy (2021 update).',
      dosingRecommendation: 'Avoid codeine use due to lack of efficacy.',
      alternativeDrugs: ['Morphine', 'Acetaminophen', 'NSAIDs', 'Non-CYP2D6 opioids'],
      monitoringAdvice: 'Monitor pain scores closely and prescribe non-CYP2D6 analgesics.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'CODEINE',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.90,
      mechanism: 'CYP2D6 enzyme activity is reduced, resulting in decreased conversion of codeine to morphine.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Codeine Therapy (2021 update).',
      dosingRecommendation: 'Use lower starting doses or consider alternative non-CYP2D6 analgesics if response is inadequate.',
      alternativeDrugs: ['Acetaminophen', 'NSAIDs', 'Morphine'],
      monitoringAdvice: 'Monitor for adequate pain relief and signs of incomplete analgesia.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'CODEINE',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'CYP2D6 enzyme activity is normal, yielding expected rate of codeine bioactivation.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Codeine Therapy (2021 update).',
      dosingRecommendation: 'Initiate codeine therapy at standard recommended doses.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard opioid monitoring for analgesia and adverse effects.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'CODEINE',
      phenotype: 'RM',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.88,
      mechanism: 'CYP2D6 enzyme activity is elevated, accelerating codeine bioactivation to morphine.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Codeine Therapy (2021 update).',
      dosingRecommendation: 'Use lowest effective dose or consider non-CYP2D6 opioids to prevent opioid toxicity.',
      alternativeDrugs: ['Non-CYP2D6 opioids', 'Acetaminophen'],
      monitoringAdvice: 'Monitor for opioid-related sedation and respiratory depression.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'CODEINE',
      phenotype: 'URM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.96,
      mechanism: 'CYP2D6 duplications lead to rapid, extensive conversion of codeine into toxic levels of morphine.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Codeine Therapy (2021 update).',
      dosingRecommendation: 'Avoid codeine due to potential for life-threatening morphine toxicity.',
      alternativeDrugs: ['Morphine', 'Acetaminophen', 'NSAIDs', 'Fentanyl'],
      monitoringAdvice: 'Strictly avoid codeine. Educate patient regarding severe opioid toxicity risk.',
    ),

    // --- CYP2C19 : CLOPIDOGREL ---
    const CpicRule(
      gene: 'CYP2C19',
      drug: 'CLOPIDOGREL',
      phenotype: 'PM',
      riskLabel: 'Ineffective',
      severity: 'critical',
      baseConfidence: 0.96,
      mechanism: 'CYP2C19 loss-of-function alleles prevent bioactivation of clopidogrel prodrug into active antiplatelet form.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C19 and Clopidogrel Therapy (2022 update).',
      dosingRecommendation: 'Avoid clopidogrel due to high risk of treatment failure and stent thrombosis.',
      alternativeDrugs: ['Prasugrel', 'Ticagrelor'],
      monitoringAdvice: 'Switch immediately to prasugrel or ticagrelor unless contraindicated.',
    ),
    const CpicRule(
      gene: 'CYP2C19',
      drug: 'CLOPIDOGREL',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.92,
      mechanism: 'CYP2C19 activity is impaired, leading to reduced active metabolite generation and diminished antiplatelet response.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C19 and Clopidogrel Therapy (2022 update).',
      dosingRecommendation: 'Consider alternative antiplatelet agent (prasugrel or ticagrelor) for ACS/PCI.',
      alternativeDrugs: ['Prasugrel', 'Ticagrelor'],
      monitoringAdvice: 'Assess cardiovascular risk features and consider platelet function testing.',
    ),
    const CpicRule(
      gene: 'CYP2C19',
      drug: 'CLOPIDOGREL',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'CYP2C19 enzyme function is normal, yielding adequate active metabolite generation.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C19 and Clopidogrel Therapy (2022 update).',
      dosingRecommendation: 'Initiate clopidogrel at standard recommended dose (75 mg daily).',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard clinical monitoring for ischemic events and bleeding.',
    ),
    const CpicRule(
      gene: 'CYP2C19',
      drug: 'CLOPIDOGREL',
      phenotype: 'RM',
      riskLabel: 'Safe',
      severity: 'low',
      baseConfidence: 0.90,
      mechanism: 'CYP2C19 gain-of-function allele increases clopidogrel activation to standard/enhanced antiplatelet level.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C19 and Clopidogrel Therapy (2022 update).',
      dosingRecommendation: 'Initiate clopidogrel at standard label dose (75 mg daily).',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor for minor bleeding risks.',
    ),
    const CpicRule(
      gene: 'CYP2C19',
      drug: 'CLOPIDOGREL',
      phenotype: 'URM',
      riskLabel: 'Adjust Dosage',
      severity: 'low',
      baseConfidence: 0.92,
      mechanism: 'CYP2C19 allele duplications accelerate active metabolite generation.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C19 and Clopidogrel Therapy (2022 update).',
      dosingRecommendation: 'Standard clopidogrel dose is effective; monitor for bleeding.',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor for clinical signs of excessive antiplatelet action or bleeding.',
    ),

    // --- CYP2C9 : WARFARIN ---
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'WARFARIN',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.95,
      mechanism: 'CYP2C9 clearance of S-warfarin is dramatically reduced, causing drug accumulation and bleeding risk.',
      cpicGuidelineCitation: 'CPIC Guideline for Pharmacogenomics-Guided Warfarin Dosing (2017).',
      dosingRecommendation: 'Reduce initial warfarin dose by 50-80% using CPIC pharmacogenomic dosing algorithm.',
      alternativeDrugs: ['DOACs (Apixaban, Rivaroxaban, Dabigatran)'],
      monitoringAdvice: 'Perform daily to bi-weekly INR monitoring during dose titration.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'WARFARIN',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.92,
      mechanism: 'CYP2C9 activity is reduced, resulting in slower S-warfarin clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for Pharmacogenomics-Guided Warfarin Dosing (2017).',
      dosingRecommendation: 'Reduce starting warfarin dose by 20-40% below standard initial dose.',
      alternativeDrugs: ['DOACs (Apixaban, Rivaroxaban)'],
      monitoringAdvice: 'Monitor INR closely during initial 2-4 weeks of therapy.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'WARFARIN',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'CYP2C9 enzyme activity is normal, producing standard rate of S-warfarin clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for Pharmacogenomics-Guided Warfarin Dosing (2017).',
      dosingRecommendation: 'Dose warfarin according to standard clinical algorithms.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard routine INR monitoring.',
    ),

    // --- SLCO1B1 : SIMVASTATIN ---
    const CpicRule(
      gene: 'SLCO1B1',
      drug: 'SIMVASTATIN',
      phenotype: 'Poor function',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.96,
      mechanism: 'OATP1B1 transporter function is impaired, raising simvastatin plasma levels and myopathy risk.',
      cpicGuidelineCitation: 'CPIC Guideline for SLCO1B1 and Statin-Associated Musculoskeletal Symptoms (2022).',
      dosingRecommendation: 'Avoid simvastatin 80mg and 40mg. Prescribe lower dose (10-20mg) or switch statin.',
      alternativeDrugs: ['Pravastatin', 'Rosuvastatin', 'Atorvastatin'],
      monitoringAdvice: 'Educate patient to report unexplained muscle pain, tenderness, or weakness immediately.',
    ),
    const CpicRule(
      gene: 'SLCO1B1',
      drug: 'SIMVASTATIN',
      phenotype: 'Decreased function',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.92,
      mechanism: 'OATP1B1 transporter activity is moderately reduced, elevating systemic simvastatin acid levels.',
      cpicGuidelineCitation: 'CPIC Guideline for SLCO1B1 and Statin-Associated Musculoskeletal Symptoms (2022).',
      dosingRecommendation: 'Limit simvastatin starting dose to ≤ 20mg daily or select alternative statin.',
      alternativeDrugs: ['Pravastatin', 'Rosuvastatin'],
      monitoringAdvice: 'Monitor serum creatine kinase (CK) if muscle symptoms develop.',
    ),
    const CpicRule(
      gene: 'SLCO1B1',
      drug: 'SIMVASTATIN',
      phenotype: 'Normal function',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'OATP1B1 hepatic uptake transporter activity is normal.',
      cpicGuidelineCitation: 'CPIC Guideline for SLCO1B1 and Statin-Associated Musculoskeletal Symptoms (2022).',
      dosingRecommendation: 'Prescribe simvastatin according to standard clinical lipid guidelines.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard routine lipid panel and routine statin safety monitoring.',
    ),

    // --- TPMT : AZATHIOPRINE ---
    const CpicRule(
      gene: 'TPMT',
      drug: 'AZATHIOPRINE',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.97,
      mechanism: 'TPMT enzyme activity is non-existent, causing cytotoxic accumulation of 6-thioguanine nucleotides (6-TGN).',
      cpicGuidelineCitation: 'CPIC Guideline for Thiopurine Methyltransferase and Thiopurine Dosing (2018).',
      dosingRecommendation: 'Reduce dose by 10-fold (10% of target dose) 3x/week, or choose non-thiopurine therapy.',
      alternativeDrugs: ['Methotrexate', 'Mycophenolate Mofetil', 'Biologic immunosuppressants'],
      monitoringAdvice: 'Monitor complete blood count (CBC) weekly; high risk of severe bone marrow suppression.',
    ),
    const CpicRule(
      gene: 'TPMT',
      drug: 'AZATHIOPRINE',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.93,
      mechanism: 'TPMT activity is reduced, increasing risk of thiopurine-induced myelosuppression.',
      cpicGuidelineCitation: 'CPIC Guideline for Thiopurine Methyltransferase and Thiopurine Dosing (2018).',
      dosingRecommendation: 'Reduce starting dose to 30-50% of target full dose.',
      alternativeDrugs: ['Non-thiopurine immunosuppressants'],
      monitoringAdvice: 'Perform CBC monitoring every 1-2 weeks during initial dose escalation.',
    ),
    const CpicRule(
      gene: 'TPMT',
      drug: 'AZATHIOPRINE',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'TPMT enzyme activity is normal, yielding standard thiopurine clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for Thiopurine Methyltransferase and Thiopurine Dosing (2018).',
      dosingRecommendation: 'Initiate azathioprine at standard recommended target dose.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard routine CBC monitoring per clinical protocol.',
    ),

    // --- DPYD : FLUOROURACIL ---
    const CpicRule(
      gene: 'DPYD',
      drug: 'FLUOROURACIL',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.98,
      mechanism: 'DPYD enzyme activity is completely lacking, preventing 5-FU inactivation and causing fatal drug exposure.',
      cpicGuidelineCitation: 'CPIC Guideline for Fluoropyrimidines and DPYD (2018 update).',
      dosingRecommendation: 'Fluorouracil and capecitabine are strictly contraindicated due to lethal toxicity risk.',
      alternativeDrugs: ['Non-fluoropyrimidine chemotherapy regimens'],
      monitoringAdvice: 'Strictly avoid fluorouracil. Prescribe non-fluoropyrimidine oncology regimen.',
    ),
    const CpicRule(
      gene: 'DPYD',
      drug: 'FLUOROURACIL',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.94,
      mechanism: 'DPYD activity is reduced, decreasing fluorouracil clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for Fluoropyrimidines and DPYD (2018 update).',
      dosingRecommendation: 'Reduce initial starting dose by 25-50% and titrate based on toxicity.',
      alternativeDrugs: ['Non-fluoropyrimidine chemotherapy options'],
      monitoringAdvice: 'Monitor closely for severe neutropenia, severe mucositis, and diarrhea.',
    ),
    const CpicRule(
      gene: 'DPYD',
      drug: 'FLUOROURACIL',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'DPYD enzyme activity is normal, yielding expected fluorouracil clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for Fluoropyrimidines and DPYD (2018 update).',
      dosingRecommendation: 'Prescribe fluorouracil according to standard oncology treatment protocols.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard routine oncology monitoring for fluoropyrimidine toxicity.',
    ),

    // --- CYP3A5 : TACROLIMUS ---
    const CpicRule(
      gene: 'CYP3A5',
      drug: 'TACROLIMUS',
      phenotype: 'PM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.96,
      mechanism: 'CYP3A5 non-expressor (*3/*3). Standard clearance rate for conventional starting doses.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP3A5 and Tacrolimus (2015 update).',
      dosingRecommendation: 'Initiate tacrolimus with standard recommended starting dose.',
      alternativeDrugs: ['Cyclosporine'],
      monitoringAdvice: 'Standard therapeutic drug monitoring (TDM) of trough blood concentrations.',
    ),
    const CpicRule(
      gene: 'CYP3A5',
      drug: 'TACROLIMUS',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.94,
      mechanism: 'CYP3A5 intermediate expressor (*1/*3). Increased tacrolimus clearance requiring higher starting dose.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP3A5 and Tacrolimus (2015 update).',
      dosingRecommendation: 'Increase starting dose 1.5 to 2 times standard recommended dose, then adjust based on TDM.',
      alternativeDrugs: ['Cyclosporine'],
      monitoringAdvice: 'Perform frequent early TDM to achieve target therapeutic blood level.',
    ),
    const CpicRule(
      gene: 'CYP3A5',
      drug: 'TACROLIMUS',
      phenotype: 'NM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.95,
      mechanism: 'CYP3A5 normal expressor (*1/*1). Rapid tacrolimus metabolism leading to delayed achievement of target concentration.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP3A5 and Tacrolimus (2015 update).',
      dosingRecommendation: 'Increase starting dose 1.5 to 2 times standard recommended dose, followed by close TDM.',
      alternativeDrugs: ['Cyclosporine'],
      monitoringAdvice: 'Intensive early TDM is mandatory to prevent organ allograft rejection.',
    ),

    // --- HLA-B : ABACAVIR ---
    const CpicRule(
      gene: 'HLA-B',
      drug: 'ABACAVIR',
      phenotype: 'Positive',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.99,
      mechanism: 'HLA-B*57:01 allele present. High risk of severe, life-threatening immunological hypersensitivity reaction.',
      cpicGuidelineCitation: 'CPIC Guideline for HLA-B Genotype and Abacavir Dosing (2014).',
      dosingRecommendation: 'Abacavir is strictly contraindicated. Select an alternative non-abacavir antiretroviral.',
      alternativeDrugs: ['Tenofovir alafenamide', 'Tenofovir disoproxil', 'Zidovudine'],
      monitoringAdvice: 'Document HLA-B*57:01 positivity in patient allergy records. Never rechallenge.',
    ),
    const CpicRule(
      gene: 'HLA-B',
      drug: 'ABACAVIR',
      phenotype: 'Negative',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'HLA-B*57:01 absent. Low risk of abacavir hypersensitivity reaction.',
      cpicGuidelineCitation: 'CPIC Guideline for HLA-B Genotype and Abacavir Dosing (2014).',
      dosingRecommendation: 'Initiate abacavir at standard recommended dose according to HIV treatment guidelines.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine clinical monitoring during therapy.',
    ),
    const CpicRule(
      gene: 'HLA-B',
      drug: 'ABACAVIR',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'HLA-B*57:01 absent. Low risk of abacavir hypersensitivity reaction.',
      cpicGuidelineCitation: 'CPIC Guideline for HLA-B Genotype and Abacavir Dosing (2014).',
      dosingRecommendation: 'Initiate abacavir at standard recommended dose.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine clinical monitoring.',
    ),

    // --- HLA-B : CARBAMAZEPINE ---
    const CpicRule(
      gene: 'HLA-B',
      drug: 'CARBAMAZEPINE',
      phenotype: 'Positive',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.99,
      mechanism: 'HLA-B*15:02 allele present. Significant risk of Stevens-Johnson syndrome (SJS) and toxic epidermal necrolysis (TEN).',
      cpicGuidelineCitation: 'CPIC Guideline for HLA-B and Carbamazepine Therapy (2017).',
      dosingRecommendation: 'Avoid carbamazepine and consider alternative antiepileptic agent.',
      alternativeDrugs: ['Valproic acid', 'Levetiracetam', 'Lamotrigine (with caution)'],
      monitoringAdvice: 'Document severe cutaneous adverse reaction risk.',
    ),
    const CpicRule(
      gene: 'HLA-B',
      drug: 'CARBAMAZEPINE',
      phenotype: 'Negative',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'HLA-B*15:02 absent. Standard risk for cutaneous adverse reactions.',
      cpicGuidelineCitation: 'CPIC Guideline for HLA-B and Carbamazepine Therapy (2017).',
      dosingRecommendation: 'Initiate carbamazepine per standard dosing guidelines.',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor for common adverse effects.',
    ),
    const CpicRule(
      gene: 'HLA-B',
      drug: 'CARBAMAZEPINE',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'HLA-B*15:02 absent. Standard risk for cutaneous adverse reactions.',
      cpicGuidelineCitation: 'CPIC Guideline for HLA-B and Carbamazepine Therapy (2017).',
      dosingRecommendation: 'Initiate carbamazepine per standard dosing guidelines.',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor for standard adverse effects.',
    ),

    // --- CYP2C9 : PHENYTOIN ---
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'PHENYTOIN',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.96,
      mechanism: 'CYP2C9 poor metabolism markedly decreases phenytoin clearance, causing drug accumulation and toxicity.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and Phenytoin Dosing (2020).',
      dosingRecommendation: 'Reduce starting dose by 50% or consider alternative non-CYP2C9 antiepileptic.',
      alternativeDrugs: ['Levetiracetam', 'Valproate', 'Topiramate'],
      monitoringAdvice: 'Therapeutic drug monitoring of total and free serum phenytoin levels.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'PHENYTOIN',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.92,
      mechanism: 'CYP2C9 intermediate metabolism leads to reduced phenytoin clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and Phenytoin Dosing (2020).',
      dosingRecommendation: 'Reduce starting maintenance dose by 25-50%.',
      alternativeDrugs: ['Levetiracetam'],
      monitoringAdvice: 'Serum concentration monitoring.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'PHENYTOIN',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'Normal CYP2C9 metabolic rate for phenytoin.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and Phenytoin Dosing (2020).',
      dosingRecommendation: 'Initiate phenytoin with standard recommended dosing.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine phenytoin serum concentration monitoring.',
    ),

    // --- CYP2D6 : TAMOXIFEN ---
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'TAMOXIFEN',
      phenotype: 'PM',
      riskLabel: 'Ineffective',
      severity: 'critical',
      baseConfidence: 0.95,
      mechanism: 'CYP2D6 poor metabolism prevents activation of tamoxifen to endoxifen, increasing risk of breast cancer recurrence.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Tamoxifen Therapy (2018).',
      dosingRecommendation: 'Avoid tamoxifen and consider alternative endocrine therapy (e.g. aromatase inhibitor).',
      alternativeDrugs: ['Anastrozole', 'Letrozole', 'Exemestane'],
      monitoringAdvice: 'Consult oncology for alternative hormonal therapy selection.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'TAMOXIFEN',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.90,
      mechanism: 'CYP2D6 intermediate metabolism leads to lower active endoxifen concentrations.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Tamoxifen Therapy (2018).',
      dosingRecommendation: 'Consider dose escalation (40 mg/day) or alternative endocrine therapy.',
      alternativeDrugs: ['Aromatase inhibitors'],
      monitoringAdvice: 'Oncology specialist review.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'TAMOXIFEN',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'Standard CYP2D6 bioactivation of tamoxifen to active endoxifen metabolite.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Tamoxifen Therapy (2018).',
      dosingRecommendation: 'Initiate tamoxifen at standard 20 mg/day dose.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard oncology monitoring for endocrine therapy.',
    ),

    // --- CYP2D6 : ONDANSETRON ---
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'ONDANSETRON',
      phenotype: 'URM',
      riskLabel: 'Ineffective',
      severity: 'high',
      baseConfidence: 0.94,
      mechanism: 'Ultra-rapid CYP2D6 metabolism clears ondansetron prematurely, causing antiemetic failure.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Ondansetron (2016).',
      dosingRecommendation: 'Avoid ondansetron. Prescribe alternative 5-HT3 antagonist not predominantly metabolized by CYP2D6 (e.g. Granisetron).',
      alternativeDrugs: ['Granisetron', 'Palonosetron'],
      monitoringAdvice: 'Monitor for nausea and vomiting breakthrough.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'ONDANSETRON',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'CYP2D6 normal metabolism produces expected therapeutic ondansetron levels.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6 and Ondansetron (2016).',
      dosingRecommendation: 'Initiate ondansetron at standard recommended dosage.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard antiemetic efficacy monitoring.',
    ),

    // --- UGT1A1 : IRINOTECAN ---
    const CpicRule(
      gene: 'UGT1A1',
      drug: 'IRINOTECAN',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.96,
      mechanism: 'UGT1A1*28 homozygosity reduces SN-38 glucuronidation, precipitating severe life-threatening neutropenia and diarrhea.',
      cpicGuidelineCitation: 'CPIC Guideline for UGT1A1 and Irinotecan Dosing (2020).',
      dosingRecommendation: 'Reduce initial irinotecan dose by 30% for high-dose regimens.',
      alternativeDrugs: ['Alternative oncology regimens'],
      monitoringAdvice: 'Frequent CBC monitoring and aggressive antidiarrheal management.',
    ),
    const CpicRule(
      gene: 'UGT1A1',
      drug: 'IRINOTECAN',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.92,
      mechanism: 'UGT1A1 intermediate metabolism increases risk of SN-38 toxicity with high irinotecan doses.',
      cpicGuidelineCitation: 'CPIC Guideline for UGT1A1 and Irinotecan Dosing (2020).',
      dosingRecommendation: 'Standard initial dose for low/medium regimens; consider reduction for high dose.',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor CBC and gastrointestinal adverse events.',
    ),
    const CpicRule(
      gene: 'UGT1A1',
      drug: 'IRINOTECAN',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'Normal UGT1A1 glucuronidation of SN-38.',
      cpicGuidelineCitation: 'CPIC Guideline for UGT1A1 and Irinotecan Dosing (2020).',
      dosingRecommendation: 'Initiate irinotecan per standard oncology protocols.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine oncology monitoring.',
    ),

    // --- CYP2C9 : CELECOXIB ---
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'CELECOXIB',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'high',
      baseConfidence: 0.94,
      mechanism: 'CYP2C9 poor metabolism markedly increases celecoxib exposure, raising cardiovascular and gastrointestinal bleeding risks.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and Nonsteroidal Anti-Inflammatory Drugs (2020).',
      dosingRecommendation: 'Initiate with 25-50% of standard lowest recommended dose.',
      alternativeDrugs: ['Acetaminophen', 'Non-CYP2C9 analgesics'],
      monitoringAdvice: 'Monitor for blood pressure changes and GI bleeding.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'CELECOXIB',
      phenotype: 'IM',
      riskLabel: 'Adjust Dosage',
      severity: 'moderate',
      baseConfidence: 0.90,
      mechanism: 'CYP2C9 intermediate metabolism moderately reduces celecoxib clearance.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and Nonsteroidal Anti-Inflammatory Drugs (2020).',
      dosingRecommendation: 'Initiate with lowest recommended dose; titrate with caution.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine monitoring for NSAID adverse effects.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'CELECOXIB',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'Normal CYP2C9 clearance of celecoxib.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and Nonsteroidal Anti-Inflammatory Drugs (2020).',
      dosingRecommendation: 'Initiate celecoxib at standard recommended dosage.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine clinical monitoring.',
    ),

    // --- CYP2C9 : IBUPROFEN ---
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'IBUPROFEN',
      phenotype: 'PM',
      riskLabel: 'Adjust Dosage',
      severity: 'high',
      baseConfidence: 0.93,
      mechanism: 'CYP2C9 poor metabolism significantly reduces clearance of S-ibuprofen.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and NSAIDs (2020).',
      dosingRecommendation: 'Initiate with lowest recommended dose and extend dosing interval, or use alternative.',
      alternativeDrugs: ['Acetaminophen'],
      monitoringAdvice: 'Monitor for GI and renal toxicity with prolonged use.',
    ),
    const CpicRule(
      gene: 'CYP2C9',
      drug: 'IBUPROFEN',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'Normal CYP2C9 clearance of ibuprofen.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2C9 and NSAIDs (2020).',
      dosingRecommendation: 'Initiate ibuprofen per standard clinical indication.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine clinical monitoring.',
    ),

    // --- CYP2D6 : AMITRIPTYLINE ---
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'AMITRIPTYLINE',
      phenotype: 'PM',
      riskLabel: 'Toxic',
      severity: 'critical',
      baseConfidence: 0.95,
      mechanism: 'CYP2D6 poor metabolism leads to high amitriptyline and nortriptyline concentrations, increasing cardiotoxicity risk.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6/CYP2C19 and Tricyclic Antidepressants (2016).',
      dosingRecommendation: 'Avoid amitriptyline or reduce starting dose by 50% with therapeutic drug monitoring.',
      alternativeDrugs: ['SSRIs (e.g. Sertraline, Citalopram)'],
      monitoringAdvice: 'ECG monitoring and plasma drug levels if amitriptyline is used.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'AMITRIPTYLINE',
      phenotype: 'URM',
      riskLabel: 'Ineffective',
      severity: 'high',
      baseConfidence: 0.92,
      mechanism: 'CYP2D6 ultra-rapid metabolism leads to subtherapeutic amitriptyline concentrations.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6/CYP2C19 and Tricyclic Antidepressants (2016).',
      dosingRecommendation: 'Avoid amitriptyline due to potential lack of efficacy. Select non-CYP2D6 antidepressant.',
      alternativeDrugs: ['SSRIs'],
      monitoringAdvice: 'Monitor depression/pain response.',
    ),
    const CpicRule(
      gene: 'CYP2D6',
      drug: 'AMITRIPTYLINE',
      phenotype: 'NM',
      riskLabel: 'Safe',
      severity: 'none',
      baseConfidence: 0.98,
      mechanism: 'Normal CYP2D6 metabolism of amitriptyline.',
      cpicGuidelineCitation: 'CPIC Guideline for CYP2D6/CYP2C19 and Tricyclic Antidepressants (2016).',
      dosingRecommendation: 'Initiate amitriptyline at standard starting dose.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine psychiatric and clinical monitoring.',
    ),
  ];

  /// Evaluates risk for a given drug using the parsed VCF result and optional dynamic evidence.
  static PgxReport evaluateDrug({
    required String drugName,
    required VcfParseResult parseResult,
    DrugEvidence? evidence,
    Map<String, dynamic>? customLlmExplanation,
    Map<String, String>? clinicalData,
  }) {
    final enteredDrug = drugName.trim().toUpperCase();
    final cleanDrug = resolveDrugName(drugName) ?? (evidence?.genericName.toUpperCase() ?? enteredDrug);

    // Case 1: Dynamic online/offline evidence is provided
    if (evidence != null) {
      if (!evidence.verifiedMedicine) {
        return _generateUnverifiedMedicineReport(
          drugName: drugName,
          parseResult: parseResult,
        );
      }

      final clinicalFinding = UniversalMedicineSafetyEngine.evaluate(
        cleanDrug,
        clinicalData,
      );
      if (clinicalFinding != null) {
        return _generateClinicalFindingReport(
          drugName: evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug,
          parseResult: parseResult,
          evidence: evidence,
          finding: clinicalFinding,
        );
      }

      if (!evidence.hasPgxRelationship) {
        final missingClinicalData = evidence.requiredClinicalData
            .where((field) => clinicalData?[field]?.trim().isNotEmpty != true)
            .toList();
        if (missingClinicalData.isNotEmpty) {
          return _generateMissingClinicalDataReport(
            drugName: evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug,
            primaryGene: 'NON-PGX',
            parseResult: parseResult,
            evidence: evidence,
            missingFields: missingClinicalData,
          );
        }
        return _generateNoPgxRelationshipReport(
          drugName: evidence.displayName.isNotEmpty ? evidence.displayName : drugName,
          evidence: evidence,
          parseResult: parseResult,
        );
      }

      final primaryGene = evidence.genes.isNotEmpty
          ? evidence.genes.first.toUpperCase()
          : (drugToGeneMap[cleanDrug] ?? 'UNMAPPED');

      if (primaryGene == 'UNMAPPED' || primaryGene == 'NONE') {
        return _generateUnknownDrugReport(enteredDrug, parseResult);
      }

      // Special check for Warfarin with missing clinical inputs
      if (cleanDrug == 'WARFARIN' && (clinicalData == null || clinicalData.isEmpty)) {
        return _generateWarfarinInsufficientDataReport(parseResult);
      }

      final geneData = parseResult.geneProfiles[primaryGene];
      final phenotype = geneData?.phenotype ?? 'Unknown';

      // If patient's VCF does not contain the gene or has unconfirmed genotype
      if (geneData == null ||
          phenotype == 'Unknown' ||
          (geneData.isInferred && geneData.variants.isEmpty)) {
        return _generateInsufficientPatientDataReport(
          drugName: evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug,
          primaryGene: primaryGene,
          parseResult: parseResult,
          geneData: geneData,
          evidence: evidence,
        );
      }

      final missingClinicalData = evidence.requiredClinicalData
          .where((field) => clinicalData?[field]?.trim().isNotEmpty != true)
          .toList();
      if (missingClinicalData.isNotEmpty) {
        return _generateMissingClinicalDataReport(
          drugName: evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug,
          primaryGene: primaryGene,
          parseResult: parseResult,
          evidence: evidence,
          missingFields: missingClinicalData,
        );
      }

      // Patient genotype is available, but only an explicit local rule may
      // classify risk. Online evidence can identify a relationship without
      // providing enough validated phenotype-specific logic for this engine.
      final matchingRules = _rules.where(
        (r) =>
            (r.gene.toUpperCase() == primaryGene.toUpperCase() || primaryGene.contains(r.gene)) &&
            (r.drug.toUpperCase() == cleanDrug.toUpperCase() || r.drug.toUpperCase() == evidence.genericName.toUpperCase()) &&
            (r.phenotype.toUpperCase() == phenotype.toUpperCase() ||
                (r.phenotype.toLowerCase().contains('poor') && phenotype.toLowerCase().contains('poor')) ||
                (r.phenotype.toLowerCase().contains('normal') && phenotype.toLowerCase().contains('normal')) ||
                (r.phenotype.toLowerCase().contains('decreased') && phenotype.toLowerCase().contains('decreased'))),
      ).toList();
      if (matchingRules.isEmpty) {
        return _generateEvidenceWithoutDeterministicRuleReport(
          drugName: evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug,
          primaryGene: primaryGene,
          phenotype: phenotype,
          parseResult: parseResult,
          geneData: geneData,
          evidence: evidence,
        );
      }
      final matchedRule = matchingRules.first;

      double finalConfidence = matchedRule.baseConfidence;
      if (geneData.isInferred) {
        finalConfidence = (finalConfidence - 0.20).clamp(0.50, 0.99);
      }

      final riskAssessment = RiskAssessment(
        riskLabel: matchedRule.riskLabel,
        confidenceScore: finalConfidence,
        severity: matchedRule.severity,
      );

      final pgxProfile = PharmacogenomicProfile(
        primaryGene: primaryGene,
        diplotype: geneData.diplotype,
        phenotype: phenotype,
        detectedVariants: geneData.variants,
      );

      final clinicalRec = ClinicalRecommendation(
        cpicGuidelineCitation: matchedRule.cpicGuidelineCitation.isNotEmpty
            ? matchedRule.cpicGuidelineCitation
            : evidence.guidelineCitation,
        dosingRecommendation: matchedRule.dosingRecommendation.isNotEmpty
            ? matchedRule.dosingRecommendation
            : evidence.dosingRecommendation,
        alternativeDrugs: matchedRule.alternativeDrugs.isNotEmpty
            ? matchedRule.alternativeDrugs
            : evidence.alternativeDrugs,
        monitoringAdvice: matchedRule.monitoringAdvice.isNotEmpty
            ? matchedRule.monitoringAdvice
            : evidence.monitoringAdvice,
        evidenceLevel: evidence.evidenceLevel,
        evidenceSource: evidence.source,
        evidenceRetrievedAt: evidence.retrievalTimestamp,
      );

      final llmExplanation = customLlmExplanation != null
          ? LlmExplanation.fromJson(customLlmExplanation)
          : LlmExplanation(
              summary: '${matchedRule.gene} $phenotype phenotype assessed for ${evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug}.',
              mechanism: matchedRule.mechanism.isNotEmpty ? matchedRule.mechanism : evidence.mechanism,
              patientFriendly: 'Your genetic test results for $primaryGene ($phenotype) suggest that ${evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug} is labeled as ${matchedRule.riskLabel}. ${matchedRule.dosingRecommendation}',
              clinicianNote: 'CPIC/PharmGKB clinical evidence evaluation: $primaryGene diplotype ${geneData.diplotype} ($phenotype). ${matchedRule.dosingRecommendation}',
            );

      return PgxReport(
        patientId: parseResult.patientId,
        drug: evidence.displayName.isNotEmpty ? evidence.displayName : cleanDrug,
        timestamp: DateTime.now().toIso8601String(),
        riskAssessment: riskAssessment,
        pharmacogenomicProfile: pgxProfile,
        clinicalRecommendation: clinicalRec,
        llmGeneratedExplanation: llmExplanation,
        qualityMetrics: parseResult.qualityMetrics,
        evidence: evidence,
      );
    }

    // Case 2: Standard Evaluation without explicit evidence instance
    final primaryGene = drugToGeneMap[cleanDrug];
    if (primaryGene == null) {
      return _generateUnknownDrugReport(enteredDrug, parseResult);
    }

    if (cleanDrug == 'WARFARIN') {
      return _generateWarfarinInsufficientDataReport(parseResult);
    }

    final geneData = parseResult.geneProfiles[primaryGene];
    final phenotype = geneData?.phenotype ?? 'Unknown';

    if (geneData == null ||
        phenotype == 'Unknown' ||
        (geneData.isInferred && geneData.variants.isEmpty)) {
      return _generateInsufficientGenotypeReport(
        drugName: cleanDrug,
        primaryGene: primaryGene,
        parseResult: parseResult,
        geneData: geneData,
      );
    }

    final matchedRule = _rules.firstWhere(
      (r) =>
          r.gene == primaryGene &&
          r.drug == cleanDrug &&
          (r.phenotype == phenotype ||
              (r.phenotype.contains('Poor') && phenotype.contains('Poor')) ||
              (r.phenotype.contains('Normal') && phenotype.contains('Normal')) ||
              (r.phenotype.contains('Decreased') && phenotype.contains('Decreased'))),
      orElse: () => _createFallbackRule(primaryGene, cleanDrug, phenotype),
    );

    double finalConfidence = matchedRule.baseConfidence;
    if (geneData.isInferred) {
      finalConfidence = (finalConfidence - 0.20).clamp(0.50, 0.99);
    }

    final riskAssessment = RiskAssessment(
      riskLabel: matchedRule.riskLabel,
      confidenceScore: finalConfidence,
      severity: matchedRule.severity,
    );

    final pgxProfile = PharmacogenomicProfile(
      primaryGene: primaryGene,
      diplotype: geneData.diplotype,
      phenotype: phenotype,
      detectedVariants: geneData.variants,
    );

    final clinicalRec = ClinicalRecommendation(
      cpicGuidelineCitation: matchedRule.cpicGuidelineCitation,
      dosingRecommendation: matchedRule.dosingRecommendation,
      alternativeDrugs: matchedRule.alternativeDrugs,
      monitoringAdvice: matchedRule.monitoringAdvice,
    );

    final llmExplanation = customLlmExplanation != null
        ? LlmExplanation.fromJson(customLlmExplanation)
        : LlmExplanation(
            summary: '${matchedRule.gene} $phenotype phenotype assessed for $cleanDrug.',
            mechanism: matchedRule.mechanism,
            patientFriendly: 'Your genetic results for $primaryGene ($phenotype) suggest that $cleanDrug is labeled as ${matchedRule.riskLabel}. ${matchedRule.dosingRecommendation}',
            clinicianNote: 'CPIC Guideline evaluation: $primaryGene diplotype ${geneData.diplotype} ($phenotype). ${matchedRule.dosingRecommendation}',
          );

    return PgxReport(
      patientId: parseResult.patientId,
      drug: cleanDrug,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: riskAssessment,
      pharmacogenomicProfile: pgxProfile,
      clinicalRecommendation: clinicalRec,
      llmGeneratedExplanation: llmExplanation,
      qualityMetrics: parseResult.qualityMetrics,
    );
  }

  /// Transparent report for drugs with NO known PGx relationship in CPIC / PharmGKB / FDA.
  static PgxReport _generateNoPgxRelationshipReport({
    required String drugName,
    required DrugEvidence evidence,
    required VcfParseResult parseResult,
  }) {
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'No major risk identified',
        confidenceScore: 0.70,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: 'NON-PGX',
        diplotype: 'N/A',
        phenotype: 'No Established PGx Association',
        detectedVariants: [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: evidence.guidelineCitation.isNotEmpty
            ? evidence.guidelineCitation
            : 'No established pharmacogenomic guidelines for this drug in CPIC, PharmGKB, or FDA biomarker tables.',
        dosingRecommendation: evidence.dosingRecommendation.isNotEmpty
            ? evidence.dosingRecommendation
            : 'Prescribe according to standard clinical dosing guidelines and manufacturer monograph.',
        alternativeDrugs: evidence.alternativeDrugs,
        monitoringAdvice: evidence.monitoringAdvice.isNotEmpty
            ? evidence.monitoringAdvice
            : 'Standard routine clinical monitoring for therapeutic response and known adverse reactions.',
        evidenceLevel: evidence.evidenceLevel,
        evidenceSource: evidence.source,
        evidenceRetrievedAt: evidence.retrievalTimestamp,
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'NO KNOWN PHARMACOGENOMIC RELATIONSHIP FOUND for $drugName. NO ACTIONABLE PGX FINDING; clinical safety checks completed with the information provided.',
        mechanism: evidence.mechanism.isNotEmpty
            ? evidence.mechanism
            : 'Current CPIC guidelines, PharmGKB databases, and FDA pharmacogenomic biomarker tables show no established germline genetic associations affecting metabolism or clinical risk for $drugName.',
        patientFriendly: 'No major medication-specific risk was identified from the patient information and validated evidence available to PharmaGuard. This does not mean the medicine is 100% safe.',
        clinicianNote: 'Comprehensive review of CPIC / PharmGKB / FDA pharmacogenomic databases identified no actionable germline biomarkers for $drugName. Dosing should follow standard clinical parameters (e.g. renal/hepatic function, weight, drug interactions).',
      ),
      qualityMetrics: parseResult.qualityMetrics,
      evidence: evidence,
    );
  }

  static PgxReport _generateUnverifiedMedicineReport({
    required String drugName,
    required VcfParseResult parseResult,
  }) {
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'Medicine not verified',
        confidenceScore: 0.0,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: 'UNMAPPED',
        diplotype: 'N/A',
        phenotype: 'Not assessed',
        detectedVariants: const [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: 'Medicine identity could not be verified.',
        dosingRecommendation: 'Please enter the exact medicine name or provide package details before assessment.',
        alternativeDrugs: const [],
        monitoringAdvice: 'No safety assessment was performed.',
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'MEDICINE NOT VERIFIED.',
        mechanism: 'The submitted name did not resolve to a verified medicine identity.',
        patientFriendly: 'PharmaGuard could not reliably identify this medicine, so it did not make a safety claim.',
        clinicianNote: 'Identity verification failed; stop assessment until the active ingredient is confirmed.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
    );
  }

  static PgxReport _generateClinicalFindingReport({
    required String drugName,
    required VcfParseResult parseResult,
    required DrugEvidence evidence,
    required ClinicalSafetyFinding finding,
  }) {
    final highRisk = finding.status == 'CONTRAINDICATED' ||
        finding.status == 'DRUG_INTERACTION_DETECTED';
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: highRisk ? finding.status : 'Use with caution',
        confidenceScore: 0.85,
        severity: highRisk ? 'critical' : 'moderate',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: evidence.genes.isEmpty ? 'NON-PGX' : evidence.genes.first,
        diplotype: 'Not applicable',
        phenotype: evidence.hasPgxRelationship ? 'Not assessed due to higher-priority clinical finding' : 'No Established PGx Association',
        detectedVariants: const [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: finding.evidenceSource,
        dosingRecommendation: finding.explanation,
        alternativeDrugs: evidence.alternativeDrugs,
        monitoringAdvice: 'Do not start, stop, or change this medicine without a qualified doctor or pharmacist.',
        evidenceLevel: evidence.evidenceLevel,
        evidenceSource: evidence.source,
        evidenceRetrievedAt: evidence.retrievalTimestamp,
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: '${finding.status}: ${finding.title}.',
        mechanism: finding.explanation,
        patientFriendly: finding.explanation,
        clinicianNote: '${finding.title}. Higher-priority clinical safety finding overrides PGx evaluation.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
      evidence: evidence,
    );
  }

  /// Report for drugs with valid PGx relationships, but patient's VCF lacks data for the required gene.
  static PgxReport _generateInsufficientPatientDataReport({
    required String drugName,
    required String primaryGene,
    required VcfParseResult parseResult,
    required ParsedGeneData? geneData,
    required DrugEvidence evidence,
  }) {
    final message = geneData?.variants.isNotEmpty == true
        ? 'The VCF contains variant calls for $primaryGene, but no definitive star-allele diplotype. Raw calls cannot be translated into a CPIC phenotype without a validated variant-to-star-allele mapping.'
        : 'The patient\'s uploaded VCF file does not contain callable sequence or genotype data for $primaryGene.';

    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'Unknown',
        confidenceScore: 0.0,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: primaryGene,
        diplotype: geneData?.diplotype ?? 'Not determined',
        phenotype: 'Unknown',
        detectedVariants: geneData?.variants ?? [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: evidence.guidelineCitation.isNotEmpty
            ? evidence.guidelineCitation
            : 'CPIC Guideline Reference for $primaryGene.',
        dosingRecommendation: 'Do NOT assume this drug is Safe. Confirm the patient\'s $primaryGene genotype before applying pharmacogenomic dosing adjustments.',
        alternativeDrugs: evidence.alternativeDrugs,
        monitoringAdvice: 'Conduct targeted $primaryGene pharmacogenetic testing or apply conventional clinical monitoring.',
        evidenceLevel: evidence.evidenceLevel,
        evidenceSource: evidence.source,
        evidenceRetrievedAt: evidence.retrievalTimestamp,
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'UNKNOWN — INSUFFICIENT PATIENT DATA for $drugName ($primaryGene).',
        mechanism: '$message Actionable guidelines exist for $drugName ($primaryGene) via ${evidence.source}, but cannot be evaluated without the patient\'s $primaryGene genotype.',
        patientFriendly: 'Your uploaded genetic file does not contain confirmed data for the $primaryGene gene, which is critical for checking $drugName safety. Please ask your clinician about targeted genetic testing.',
        clinicianNote: '$message CPIC / PharmGKB Level A/B evidence exists for $drugName and $primaryGene. Normal function (*1/*1) cannot be assumed from an uncalled gene.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
      evidence: evidence,
    );
  }

  static PgxReport _generateMissingClinicalDataReport({
    required String drugName,
    required String primaryGene,
    required VcfParseResult parseResult,
    required DrugEvidence evidence,
    required List<String> missingFields,
  }) {
    final fields = missingFields.join(', ');
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'Unknown',
        confidenceScore: 0.0,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: primaryGene,
        diplotype: 'Not determined',
        phenotype: 'Unknown',
        detectedVariants: const [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: evidence.guidelineCitation,
        dosingRecommendation:
            'Do not classify this medicine until the required clinical data are supplied: $fields.',
        alternativeDrugs: evidence.alternativeDrugs,
        monitoringAdvice: evidence.monitoringAdvice,
        evidenceLevel: evidence.evidenceLevel,
        evidenceSource: evidence.source,
        evidenceRetrievedAt: evidence.retrievalTimestamp,
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'UNKNOWN — REQUIRED CLINICAL DATA MISSING for $drugName.',
        mechanism: 'The validated evidence requires additional clinical inputs before a deterministic assessment can be made.',
        patientFriendly: 'The genetic result alone is not enough for this medicine. The following information is needed: $fields.',
        clinicianNote: 'Required clinical data missing: $fields. No risk classification was generated.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
      evidence: evidence,
    );
  }

  static PgxReport _generateEvidenceWithoutDeterministicRuleReport({
    required String drugName,
    required String primaryGene,
    required String phenotype,
    required VcfParseResult parseResult,
    required ParsedGeneData geneData,
    required DrugEvidence evidence,
  }) {
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'Unknown',
        confidenceScore: 0.0,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: primaryGene,
        diplotype: geneData.diplotype,
        phenotype: phenotype,
        detectedVariants: geneData.variants,
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: evidence.guidelineCitation,
        dosingRecommendation: 'No risk classification was generated because this build has no validated deterministic rule for $primaryGene $phenotype and $drugName.',
        alternativeDrugs: evidence.alternativeDrugs,
        monitoringAdvice: evidence.monitoringAdvice,
        evidenceLevel: evidence.evidenceLevel,
        evidenceSource: evidence.source,
        evidenceRetrievedAt: evidence.retrievalTimestamp,
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'UNKNOWN — DETERMINISTIC RULE NOT AVAILABLE for $drugName.',
        mechanism: 'Evidence was found for $primaryGene, but an online evidence mention alone cannot be converted into a patient-specific risk classification.',
        patientFriendly: 'Pharmacogenomic evidence exists for this medicine, but PharmaGuard does not yet have a validated local rule to classify your result.',
        clinicianNote: 'Do not infer Safe, Toxic, Ineffective, or Adjust Dosage from the discovered evidence without a validated phenotype-specific rule.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
      evidence: evidence,
    );
  }

  static PgxReport _generateUnknownDrugReport(String drugName, VcfParseResult parseResult) {
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'Unknown',
        confidenceScore: 0.30,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: 'UNMAPPED',
        diplotype: 'N/A',
        phenotype: 'Unknown',
        detectedVariants: [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: 'No validated local or online PGx rule mapping is available for $drugName.',
        dosingRecommendation: 'Consult a clinical pharmacologist or pharmacist for expert evaluation of $drugName.',
        alternativeDrugs: [],
        monitoringAdvice: 'Standard clinical monitoring per drug package insert guidelines.',
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'Pharmacogenomic rules for $drugName are not available in current evidence databases.',
        mechanism: 'PharmaGuard evaluated local guidelines and authoritative online PGx databases, but found no verified CPIC/PharmGKB mapping for "$drugName".',
        patientFriendly: 'We currently do not have automated genomic risk rules for "$drugName". Please consult your prescribing physician or pharmacist.',
        clinicianNote: 'Unrecognized or unmapped drug target "$drugName". Automated rule engine score defaulted to Unknown.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
    );
  }

  static PgxReport _generateInsufficientGenotypeReport({
    required String drugName,
    required String primaryGene,
    required VcfParseResult parseResult,
    required ParsedGeneData? geneData,
  }) {
    final message = geneData?.variants.isNotEmpty == true
        ? 'The VCF contains variant calls for $primaryGene, but no star-allele diplotype. Raw FORMAT/GT calls cannot be translated into a CPIC phenotype without a validated variant-to-star-allele mapping.'
        : 'The VCF does not contain a confirmed, callable genotype for the relevant pharmacogene.';
    return PgxReport(
      patientId: parseResult.patientId,
      drug: drugName,
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(
        riskLabel: 'Unknown',
        confidenceScore: 0.0,
        severity: 'none',
      ),
      pharmacogenomicProfile: PharmacogenomicProfile(
        primaryGene: primaryGene,
        diplotype: geneData?.diplotype ?? 'Not determined',
        phenotype: 'Unknown',
        detectedVariants: geneData?.variants ?? [],
      ),
      clinicalRecommendation: ClinicalRecommendation(
        cpicGuidelineCitation: 'No genotype-based recommendation can be made until $primaryGene is called from a validated PGx assay.',
        dosingRecommendation: 'Do not treat this as Safe. Confirm the $primaryGene genotype before using a pharmacogenomic dosing recommendation.',
        alternativeDrugs: [],
        monitoringAdvice: 'Use standard clinical assessment and consult the prescriber or pharmacist while confirmatory testing is obtained.',
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'No safety label was assigned for $drugName because the relevant $primaryGene genotype is not confirmed.',
        mechanism: message,
        patientFriendly: 'Your file does not provide enough confirmed genetic information for $primaryGene to call $drugName safe or unsafe. Please ask your clinician about confirmatory pharmacogenetic testing.',
        clinicianNote: '$message A normal (*1/*1) result must not be assumed from an absent VCF annotation.',
      ),
      qualityMetrics: parseResult.qualityMetrics,
    );
  }

  static PgxReport _generateWarfarinInsufficientDataReport(VcfParseResult parseResult) {
    final geneData = parseResult.geneProfiles['CYP2C9'];
    const message = 'Warfarin dosing requires a validated multivariable algorithm, including VKORC1 status and clinical factors such as age, body size, indication, interacting medicines, and INR. Complete multivariable data must be supplied.';
    return PgxReport(
      patientId: parseResult.patientId,
      drug: 'WARFARIN',
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(riskLabel: 'Unknown', confidenceScore: 0.0, severity: 'none'),
      pharmacogenomicProfile: PharmacogenomicProfile(primaryGene: 'CYP2C9', diplotype: geneData?.diplotype ?? 'Not determined', phenotype: geneData?.phenotype ?? 'Unknown', detectedVariants: geneData?.variants ?? []),
      clinicalRecommendation: ClinicalRecommendation(cpicGuidelineCitation: 'CPIC Guideline for Pharmacogenomics-Guided Warfarin Dosing (2017).', dosingRecommendation: 'Do not derive a warfarin dose from this report alone. Use a validated clinical dosing tool with complete genetic and clinical inputs.', alternativeDrugs: const [], monitoringAdvice: 'Obtain the missing required inputs and manage INR under clinician supervision.'),
      llmGeneratedExplanation: LlmExplanation(summary: 'No warfarin classification was generated because required multivariable inputs are incomplete.', mechanism: message, patientFriendly: 'Genetic information in this file alone is not enough to determine a warfarin dose or safety category. Please discuss complete dosing assessment with your clinician.', clinicianNote: message),
      qualityMetrics: parseResult.qualityMetrics,
    );
  }

  static CpicRule _createFallbackRule(String gene, String drug, String phenotype) {
    return CpicRule(
      gene: gene,
      drug: drug,
      phenotype: phenotype,
      riskLabel: 'Unknown',
      severity: 'none',
      baseConfidence: 0.60,
      mechanism: '$gene phenotype $phenotype detected for $drug.',
      cpicGuidelineCitation: 'CPIC Guideline Reference for $gene.',
      dosingRecommendation: 'Follow standard clinical guidelines for $drug.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine clinical monitoring.',
    );
  }
}
