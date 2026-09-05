import '../models/pgx_report.dart';
import '../parser/vcf_parser.dart';

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
    'CODEINE': 'CYP2D6',
    'CLOPIDOGREL': 'CYP2C19',
    'WARFARIN': 'CYP2C9',
    'SIMVASTATIN': 'SLCO1B1',
    'AZATHIOPRINE': 'TPMT',
    'FLUOROURACIL': 'DPYD',
  };

  /// Common generic, brand, and spelling variants that resolve to a drug for
  /// which this on-device rule set contains a validated recommendation.  AI is
  /// used to explain a result, never to invent a clinical gene/drug mapping.
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
  };

  /// Resolves a user-entered drug to a validated canonical rule name.
  /// Returns null when the local clinical catalogue has no safe mapping.
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
  ];

  /// Evaluates risk for a given drug using the parsed VCF result.
  static PgxReport evaluateDrug({
    required String drugName,
    required VcfParseResult parseResult,
    Map<String, dynamic>? customLlmExplanation,
  }) {
    final enteredDrug = drugName.trim().toUpperCase();
    final cleanDrug = resolveDrugName(drugName);
    final primaryGene = cleanDrug == null ? null : drugToGeneMap[cleanDrug];

    if (primaryGene == null || cleanDrug == null) {
      // Free-text unmapped/unsupported drug
      return _generateUnknownDrugReport(enteredDrug, parseResult);
    }

    // Warfarin dosing is multivariable. This panel does not yet call VKORC1
    // and has no validated clinical-input dosing algorithm, so CYP2C9 alone
    // must never produce Safe/Adjust Dosage/Toxic output.
    if (cleanDrug == 'WARFARIN') {
      return _generateWarfarinInsufficientDataReport(parseResult);
    }

    final geneData = parseResult.geneProfiles[primaryGene];
    final phenotype = geneData?.phenotype ?? 'Unknown';

    // Never convert missing or inferred-without-variant VCF data into a
    // normal-metabolizer "Safe" result.
    if (geneData == null || phenotype == 'Unknown' ||
        (geneData.isInferred && geneData.variants.isEmpty)) {
      return _generateInsufficientGenotypeReport(
        drugName: cleanDrug,
        primaryGene: primaryGene,
        parseResult: parseResult,
        geneData: geneData,
      );
    }

    final matchedRule = _rules.firstWhere(
      (r) => r.gene == primaryGene && (r.phenotype == phenotype || (r.phenotype.contains('Poor') && phenotype.contains('Poor'))),
      orElse: () => _createFallbackRule(primaryGene, cleanDrug, phenotype),
    );

    double finalConfidence = matchedRule.baseConfidence;
    if (geneData.isInferred == true) {
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
        cpicGuidelineCitation: 'No validated local deterministic PGx rule mapping is available for $drugName in this panel.',
        dosingRecommendation: 'Consult a clinical pharmacologist or clinical pharmacist for expert evaluation of $drugName.',
        alternativeDrugs: [],
        monitoringAdvice: 'Standard clinical monitoring per drug package insert guidelines.',
      ),
      llmGeneratedExplanation: LlmExplanation(
        summary: 'Pharmacogenomic rules for $drugName are not included in the current 6-gene panel.',
        mechanism: 'PharmaGuard currently validates CYP2D6, CYP2C19, CYP2C9, SLCO1B1, TPMT, and DPYD. $drugName is not mapped to these 6 genes.',
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
    const message = 'Warfarin dosing requires a validated multivariable algorithm, including VKORC1 status and clinical factors such as age, body size, indication, interacting medicines, and INR. This local panel does not yet implement that complete algorithm.';
    return PgxReport(
      patientId: parseResult.patientId,
      drug: 'WARFARIN',
      timestamp: DateTime.now().toIso8601String(),
      riskAssessment: RiskAssessment(riskLabel: 'Unknown', confidenceScore: 0.0, severity: 'none'),
      pharmacogenomicProfile: PharmacogenomicProfile(primaryGene: 'CYP2C9', diplotype: geneData?.diplotype ?? 'Not determined', phenotype: geneData?.phenotype ?? 'Unknown', detectedVariants: geneData?.variants ?? []),
      clinicalRecommendation: ClinicalRecommendation(cpicGuidelineCitation: 'CPIC Guideline for Pharmacogenomics-Guided Warfarin Dosing (2017).', dosingRecommendation: 'Do not derive a warfarin dose from this report. Use a validated clinical dosing tool with complete genetic and clinical inputs.', alternativeDrugs: const [], monitoringAdvice: 'Obtain the missing required inputs and manage INR under clinician supervision.'),
      llmGeneratedExplanation: LlmExplanation(summary: 'No warfarin classification was generated because the required dosing inputs are incomplete.', mechanism: message, patientFriendly: 'Genetic information in this file alone is not enough to determine a warfarin dose or safety category. Please discuss complete dosing assessment with your clinician.', clinicianNote: message),
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
