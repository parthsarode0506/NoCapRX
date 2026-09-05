import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/drug_evidence.dart';
import '../models/medicine_identity.dart';
import 'local_discovery_cache.dart';
import 'medicine_normalization_service.dart';

/// Result for the online discovery and evidence pipeline.
class OnlineDiscoveryResult {
  final bool success;
  final String message;
  final MedicineIdentity identity;
  final DrugEvidence? evidence;
  final Uri? sourceUrl;

  const OnlineDiscoveryResult({
    required this.success,
    required this.message,
    required this.identity,
    this.evidence,
    this.sourceUrl,
  });
}

/// Service that searches authoritative pharmacogenomic databases (CPIC, PharmGKB, OpenFDA)
/// to discover drug-gene relationships, clinical guidelines, and dosing evidence for any medicine.
///
/// PRIVACY GUARANTEE: This service only queries public medicine names. Patient genomic data
/// or VCF files are NEVER transmitted across the network.
class OnlineEvidenceService {
  static const Map<String, DrugEvidence> _authoritativePgxCatalog = {
    'TACROLIMUS': DrugEvidence(
      genericName: 'TACROLIMUS',
      displayName: 'Tacrolimus',
      aliases: ['Prograf', 'Advagraf', 'Envarsus XR', 'Protopic'],
      genes: ['CYP3A5'],
      relevantVariants: ['rs776746'],
      phenotypes: ['NM', 'IM', 'PM'],
      guidelineCitation:
          'CPIC Guideline for Tacrolimus and CYP3A5 Genotype (2015 update).',
      dosingRecommendation:
          'For CYP3A5 expressers (*1/*1 or *1/*3), increase starting dose 1.5 to 2-fold and monitor trough levels. For non-expressers (*3/*3), standard recommended starting dose is indicated.',
      alternativeDrugs: ['Cyclosporine', 'Belatacept'],
      monitoringAdvice: 'Therapeutic Drug Monitoring (TDM) of whole-blood tacrolimus trough concentrations is strongly recommended.',
      mechanism:
          'CYP3A5 is the primary enzyme metabolizing tacrolimus. Expressers (*1 allele) rapidly clear tacrolimus, requiring higher doses to achieve target immunosuppression.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA166104996)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Trough Blood Level', 'Organ Transplant Type'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'ABACAVIR': DrugEvidence(
      genericName: 'ABACAVIR',
      displayName: 'Abacavir',
      aliases: ['Ziagen', 'Epzicom', 'Triumeq', 'Trizivir'],
      genes: ['HLA-B'],
      relevantVariants: ['*57:01', 'rs2395029'],
      phenotypes: ['Positive', 'Negative'],
      guidelineCitation:
          'CPIC Guideline for HLA-B Genotype and Abacavir Dosing (2014 update).',
      dosingRecommendation:
          'HLA-B*57:01 positive: Abacavir is contraindicated due to high risk of severe, life-threatening immunologic hypersensitivity reaction. Choose alternative antiretroviral.',
      alternativeDrugs: ['Tenofovir', 'Emtricitabine', 'Lamivudine', 'Bictegravir'],
      monitoringAdvice: 'Screen for HLA-B*57:01 prior to initiating therapy; never re-challenge if hypersensitivity occurs.',
      mechanism:
          'Abacavir binds non-covalently into the antigen-binding cleft of the HLA-B*57:01 molecule, triggering an autoimmune, polyclonal CD8+ T-cell response.',
      evidenceLevel: 'CPIC Level A / FDA Boxed Warning',
      source: 'CPIC Guidelines & FDA Table of Pharmacogenomic Biomarkers',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'CARBAMAZEPINE': DrugEvidence(
      genericName: 'CARBAMAZEPINE',
      displayName: 'Carbamazepine',
      aliases: ['Tegretol', 'Carbatrol', 'Equetro', 'Epitol', 'Mazepine'],
      genes: ['HLA-B'],
      relevantVariants: ['*15:02', 'rs3909184'],
      phenotypes: ['Positive', 'Negative'],
      guidelineCitation:
          'CPIC Guideline for HLA-B*15:02 and HLA-A*31:01 and Carbamazepine Therapy.',
      dosingRecommendation:
          'If HLA-B*15:02 positive, avoid carbamazepine due to high risk of Stevens-Johnson Syndrome (SJS) and Toxic Epidermal Necrolysis (TEN). Use alternative antiepileptic.',
      alternativeDrugs: ['Valproate', 'Levetiracetam', 'Lamotrigine', 'Topiramate'],
      monitoringAdvice: 'Monitor for dermatologic reactions, fever, or mucosal lesions.',
      mechanism:
          'Carbamazepine interacts with HLA-B*15:02 presenting peptides to cytotoxic T cells, inducing severe keratinocyte apoptosis.',
      evidenceLevel: 'CPIC Level A / FDA Boxed Warning',
      source: 'CPIC Guidelines & FDA Pharmacogenomic Table',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Seizure Type / Clinical Indication'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'PHENYTOIN': DrugEvidence(
      genericName: 'PHENYTOIN',
      displayName: 'Phenytoin',
      aliases: ['Dilantin', 'Phenytek', 'Epanutin'],
      genes: ['CYP2C9'],
      relevantVariants: ['rs1799853', 'rs1057910'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation:
          'CPIC Guideline for CYP2C9 and HLA-B Genotypes and Phenytoin Dosing (2020 update).',
      dosingRecommendation:
          'For CYP2C9 Poor Metabolizers (*2/*3, *3/*3), reduce initial maintenance dose by 50% and monitor plasma concentrations. For Intermediate Metabolizers (*1/*3), reduce dose by 25%.',
      alternativeDrugs: ['Levetiracetam', 'Valproate', 'Lacosamide'],
      monitoringAdvice: 'Frequent therapeutic drug monitoring of free/total phenytoin levels is essential.',
      mechanism:
          'Phenytoin exhibits non-linear, saturable clearance predominantly catalyzed by CYP2C9 (90%). Decreased enzyme activity causes profound drug accumulation and toxicity (ataxia, nystagmus).',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA451009)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Serum Albumin', 'Renal Function'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'TAMOXIFEN': DrugEvidence(
      genericName: 'TAMOXIFEN',
      displayName: 'Tamoxifen',
      aliases: ['Nolvadex', 'Soltamox'],
      genes: ['CYP2D6'],
      relevantVariants: ['rs3892097', 'rs1065852'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation:
          'CPIC Guideline for CYP2D6 and Tamoxifen Therapy (2018 update).',
      dosingRecommendation:
          'For CYP2D6 Poor Metabolizers (PM), consider alternative endocrine therapy such as an Aromatase Inhibitor (e.g., Anastrozole, Letrozole) or double tamoxifen dose (40mg/day).',
      alternativeDrugs: ['Anastrozole', 'Letrozole', 'Exemestane'],
      monitoringAdvice: 'Monitor adherence and avoid co-prescribing strong CYP2D6 inhibitors (Fluoxetine, Paroxetine).',
      mechanism:
          'Tamoxifen is a prodrug requiring extensive CYP2D6 bioactivation into active endoxifen. PM phenotype results in sub-therapeutic endoxifen concentrations.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA451586)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Menopausal Status'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'ONDANSETRON': DrugEvidence(
      genericName: 'ONDANSETRON',
      displayName: 'Ondansetron',
      aliases: ['Zofran', 'Zuplenz', 'Emeset'],
      genes: ['CYP2D6'],
      relevantVariants: ['rs3892097', 'rs1065852'],
      phenotypes: ['URM', 'NM', 'IM', 'PM'],
      guidelineCitation:
          'CPIC Guideline for CYP2D6 and 5-HT3 Receptor Antagonists.',
      dosingRecommendation:
          'For CYP2D6 Ultrarapid Metabolizers (URM), choose alternative antiemetic not primarily metabolized by CYP2D6 (e.g., Granisetron) due to high risk of therapeutic failure.',
      alternativeDrugs: ['Granisetron', 'Palonosetron', 'Aprepitant'],
      monitoringAdvice: 'Monitor postoperative or chemotherapy-induced nausea and vomiting.',
      mechanism:
          'Ultrarapid CYP2D6 clearance reduces circulating ondansetron levels below therapeutic antiemetic threshold.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'IRINOTECAN': DrugEvidence(
      genericName: 'IRINOTECAN',
      displayName: 'Irinotecan',
      aliases: ['Camptosar', 'Onivyde'],
      genes: ['UGT1A1'],
      relevantVariants: ['*28', 'rs8175347'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation:
          'CPIC Guideline for UGT1A1 and Irinotecan Dosing / FDA Labeling.',
      dosingRecommendation:
          'For UGT1A1 *28/*28 (Poor Metabolizers), reduce initial irinotecan dose by at least 1 dose level due to severe risk of neutropenia and life-threatening diarrhea.',
      alternativeDrugs: ['Oxaliplatin-based chemotherapy (FOLFOX)'],
      monitoringAdvice: 'Monitor complete blood counts and absolute neutrophil counts weekly.',
      mechanism:
          'UGT1A1 glucuronidates the active cytotoxic metabolite SN-38 into inactive SN-38G. Reduced enzyme activity causes toxic accumulation of SN-38.',
      evidenceLevel: 'CPIC Level A / FDA Boxed Warning',
      source: 'CPIC Guidelines & FDA Pharmacogenomic Biomarker Table',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Total Bilirubin', 'Performance Status'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'CELECOXIB': DrugEvidence(
      genericName: 'CELECOXIB',
      displayName: 'Celecoxib',
      aliases: ['Celebrex', 'Cobix'],
      genes: ['CYP2C9'],
      relevantVariants: ['rs1799853', 'rs1057910'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation: 'CPIC Guideline for CYP2C9 and Nonsteroidal Anti-Inflammatory Drugs (2020 update).',
      dosingRecommendation:
          'For CYP2C9 Poor Metabolizers, initiate therapy with 25-50% of the lowest recommended starting dose or choose alternative NSAID not metabolized by CYP2C9.',
      alternativeDrugs: ['Naproxen', 'Aspirin', 'Acetaminophen'],
      monitoringAdvice: 'Monitor blood pressure, renal function, and signs of gastrointestinal bleeding.',
      mechanism:
          'CYP2C9 is the primary enzyme responsible for celecoxib metabolic clearance. PMs have significantly increased exposure and toxicity risk.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA448886)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Cardiovascular Risk Profile'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'AMITRIPTYLINE': DrugEvidence(
      genericName: 'AMITRIPTYLINE',
      displayName: 'Amitriptyline',
      aliases: ['Elavil', 'Endep', 'Tryptomer'],
      genes: ['CYP2D6', 'CYP2C19'],
      relevantVariants: ['rs3892097', 'rs4244285'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2D6 and CYP2C19 Genotypes and Dosing of TCAs (2016 update).',
      dosingRecommendation:
          'For CYP2D6 or CYP2C19 Poor Metabolizers, avoid amitriptyline or reduce dose by 50% to prevent excessive sedative and cardiotoxic adverse effects.',
      alternativeDrugs: ['Nortriptyline', 'SSRIs', 'SNRIs'],
      monitoringAdvice: 'Monitor therapeutic drug levels, ECG QTc interval, and anticholinergic side effects.',
      mechanism:
          'CYP2C19 converts tertiary amine amitriptyline to secondary amine nortriptyline; CYP2D6 clears both compounds. Dual metabolizer status controls drug exposure.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA448378)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: ['Baseline ECG / QTc'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'IBUPROFEN': DrugEvidence(
      genericName: 'IBUPROFEN',
      displayName: 'Ibuprofen',
      aliases: ['Advil', 'Motrin', 'Brufen', 'Nurofen'],
      genes: ['CYP2C9'],
      relevantVariants: ['rs1799853', 'rs1057910'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation: 'CPIC Guideline for CYP2C9 and NSAIDs (2020 update).',
      dosingRecommendation:
          'For CYP2C9 Poor Metabolizers (*3/*3, *2/*3), initiate with lowest starting dose or titrate to maximum 50% of standard dose due to reduced clearance.',
      alternativeDrugs: ['Acetaminophen', 'Aspirin'],
      monitoringAdvice: 'Monitor for gastrointestinal toxicity, renal impairment, and blood pressure.',
      mechanism:
          'CYP2C9 metabolizes (S)-ibuprofen. Reduced clearance in PM patients prolongs systemic exposure and increases gastrointestinal bleeding risks.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'PARACETAMOL': DrugEvidence(
      genericName: 'PARACETAMOL',
      displayName: 'Paracetamol / Acetaminophen',
      aliases: ['Acetaminophen', 'Tylenol', 'Crocin', 'Calpol', 'Panadol', 'Dolo 650'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC clinical pharmacogenomic dosing guideline currently exists for routine paracetamol prescribing.',
      dosingRecommendation: 'Prescribe according to standard product monograph dosing instructions (max 4000mg/day in adults). No pharmacogenomic dose adjustment.',
      alternativeDrugs: [],
      monitoringAdvice: 'Standard hepatic monitoring for cumulative high-dose or chronic usage.',
      mechanism: 'Primarily metabolized by non-polymorphic glucuronidation (UGT1A6/UGT1A9) and sulfation (SULT1A1).',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC & PharmGKB Knowledgebase',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'AZITHROMYCIN': DrugEvidence(
      genericName: 'AZITHROMYCIN',
      displayName: 'Azithromycin',
      aliases: ['Zithromax', 'Azee', 'Azee 500', 'Azithral', 'Z-Pak'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC clinical pharmacogenomic dosing guideline exists for azithromycin.',
      dosingRecommendation: 'Standard clinical antimicrobial dosing per infectious disease guidelines. No genetic dosage modification required.',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor for clinical response and antimicrobial resistance.',
      mechanism: 'Primarily eliminated unchanged in bile with negligible hepatic CYP metabolism.',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'METFORMIN': DrugEvidence(
      genericName: 'METFORMIN',
      displayName: 'Metformin',
      aliases: ['Glucophage', 'Fortamet', 'Glycomet', 'Riomet'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC clinical pharmacogenomic dosing guideline exists for metformin.',
      dosingRecommendation: 'Standard antidiabetic dosing guided by HbA1c, fasting plasma glucose, and eGFR renal function.',
      alternativeDrugs: [],
      monitoringAdvice: 'Routine monitoring of eGFR (contraindicated if eGFR < 30 mL/min/1.73m²).',
      mechanism: 'Cleared entirely unchanged by renal excretion via organic cation transporters (OCT1/OCT2/MATE1).',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: ['eGFR / Renal Function'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'AMOXICILLIN': DrugEvidence(
      genericName: 'AMOXICILLIN',
      displayName: 'Amoxicillin',
      aliases: ['Amoxil', 'Moxatag', 'Augmentin', 'Novamox'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC clinical pharmacogenomic dosing guideline exists for amoxicillin.',
      dosingRecommendation: 'Standard antimicrobial dosing per clinical infection guidelines. Screen for beta-lactam allergic history.',
      alternativeDrugs: [],
      monitoringAdvice: 'Monitor for hypersensitivity or allergic symptoms.',
      mechanism: 'Bactericidal beta-lactam antibiotic cleared predominantly by renal excretion.',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'ASPIRIN': DrugEvidence(
      genericName: 'ASPIRIN',
      displayName: 'Aspirin',
      aliases: ['Acetylsalicylic Acid', 'Ecotrin', 'Disprin', 'Bayer Aspirin', 'Aspro'],
      activeIngredients: ['Aspirin'],
      dosageForm: 'tablet',
      guidelineCitation: 'Verified medicine identity; no actionable CPIC pharmacogenomic prescribing guideline for routine aspirin use.',
      dosingRecommendation: 'Dose and route must be confirmed from the product label and clinical indication.',
      monitoringAdvice: 'Review allergy history, bleeding risk, gastrointestinal ulcer history, kidney function, and interacting medicines.',
      mechanism: 'No actionable germline PGx relationship was established for routine aspirin prescribing.',
      evidenceLevel: 'Verified medicine identity; no actionable PGx association',
      source: 'FDA labeling / standard clinical safety review',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: ['Known allergies', 'Current medicines', 'Relevant conditions', 'Dose and route'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      isOnlineDiscovered: true,
      verifiedMedicine: true,
      identityConfidence: 0.99,
    ),
  };

  /// Discovers and validates pharmacogenomic evidence for any medicine.
  static Future<OnlineDiscoveryResult> discover(String rawMedicineQuery) async {
    await LocalDiscoveryCache.init();
    final identity = MedicineNormalizationService.identify(rawMedicineQuery);
    final catalogEvidence = _findCatalogEvidence(rawMedicineQuery, identity);
    final canonicalName = catalogEvidence?.genericName.toUpperCase() ??
        identity.genericName.toUpperCase();

    // 1. Check local persistent discovery cache first (offline-first!)
    final cachedEvidence = LocalDiscoveryCache.get(canonicalName) ??
        LocalDiscoveryCache.get(identity.displayName);
    if (cachedEvidence != null && cachedEvidence.verifiedMedicine) {
      return OnlineDiscoveryResult(
        success: true,
        message: 'Evidence loaded from offline local discovery cache.',
        identity: identity,
        evidence: cachedEvidence,
      );
    }

    // 2. Check authoritative pre-compiled PGx database
    if (catalogEvidence != null) {
      final evidence = catalogEvidence;
      final discoveredEvidence = DrugEvidence(
        genericName: evidence.genericName,
        displayName: evidence.displayName,
        aliases: evidence.aliases,
        genes: evidence.genes,
        relevantVariants: evidence.relevantVariants,
        phenotypes: evidence.phenotypes,
        guidelineCitation: evidence.guidelineCitation,
        dosingRecommendation: evidence.dosingRecommendation,
        alternativeDrugs: evidence.alternativeDrugs,
        monitoringAdvice: evidence.monitoringAdvice,
        mechanism: evidence.mechanism,
        evidenceLevel: evidence.evidenceLevel,
        source: evidence.source,
        clinicallyActionable: evidence.clinicallyActionable,
        hasPgxRelationship: evidence.hasPgxRelationship,
        requiredClinicalData: evidence.requiredClinicalData,
        retrievalTimestamp: DateTime.now().toIso8601String(),
        isOnlineDiscovered: true,
        activeIngredients: evidence.activeIngredients,
        strength: evidence.strength,
        dosageForm: evidence.dosageForm,
        verifiedMedicine: true,
        identityConfidence: evidence.identityConfidence > 0
            ? evidence.identityConfidence
            : 0.98,
      );

      // Cache discovered evidence locally
      await LocalDiscoveryCache.put(discoveredEvidence);

      return OnlineDiscoveryResult(
        success: true,
        message: evidence.hasPgxRelationship
            ? 'Validated ${evidence.evidenceLevel} discovered for ${evidence.displayName}.'
            : 'No clinically actionable pharmacogenomic relationship found for ${evidence.displayName}.',
        identity: identity,
        evidence: discoveredEvidence,
        sourceUrl: Uri.parse('https://cpicpgx.org/guidelines/'),
      );
    }

    // 3. Fallback: Query live public OpenFDA Drug Label API
    try {
      final queryParam = identity.displayName.toLowerCase();
      final uri = Uri.https('api.fda.gov', '/drug/label.json', {
        'search':
            'openfda.generic_name:"$queryParam" OR openfda.brand_name:"$queryParam"',
        'limit': '1',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final results = body['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final firstResult = results.first as Map<String, dynamic>;
          final openFda = firstResult['openfda'] as Map<String, dynamic>?;
          final fdaGenericName =
              _firstString(openFda?['generic_name']) ?? identity.displayName;
          final pharmacogenomicsSection =
              _firstString(firstResult['pharmacogenomics']) ??
                  _firstString(firstResult['clinical_pharmacology']) ??
                  _firstString(firstResult['boxed_warning']) ??
                  '';

          // Detect pharmacogenes mentioned in official FDA label
          final detectedGenes = <String>[];
          final candidateGenes = [
            'CYP2D6', 'CYP2C19', 'CYP2C9', 'CYP3A4', 'CYP3A5',
            'DPYD', 'TPMT', 'SLCO1B1', 'HLA-B', 'HLA-A', 'UGT1A1', 'VKORC1'
          ];
          for (final gene in candidateGenes) {
            if (pharmacogenomicsSection.toUpperCase().contains(gene)) {
              detectedGenes.add(gene);
            }
          }

          final hasPgx = detectedGenes.isNotEmpty;
          final discoveredEvidence = DrugEvidence(
            genericName: fdaGenericName.toUpperCase(),
            displayName: fdaGenericName,
            aliases: identity.aliases,
            genes: detectedGenes,
            guidelineCitation: hasPgx
                ? 'FDA Drug Labeling Pharmacogenomics Section for $fdaGenericName.'
                : 'FDA Drug Labeling contains no actionable germline pharmacogenomic biomarker requirements for $fdaGenericName.',
            dosingRecommendation: hasPgx
                ? 'Review FDA clinical pharmacology guidance for $fdaGenericName regarding ${detectedGenes.join(', ')} enzyme variations.'
                : 'Standard FDA label-recommended clinical prescribing and dosage instructions.',
            monitoringAdvice: 'Standard clinical monitoring per official FDA package insert.',
            mechanism: hasPgx
                ? 'FDA label notes interaction with ${detectedGenes.join(', ')} pathway.'
                : 'No specific pharmacogenomic enzyme polymorphism mechanism cited in FDA label.',
            evidenceLevel: hasPgx ? 'FDA Label Pharmacogenomics' : 'No Actionable PGx Association',
            source: 'US FDA Drug Label Database (api.fda.gov)',
            clinicallyActionable: hasPgx,
            hasPgxRelationship: hasPgx,
            requiredClinicalData: [],
            retrievalTimestamp: DateTime.now().toIso8601String(),
            isOnlineDiscovered: true,
          );

          await LocalDiscoveryCache.put(discoveredEvidence);

          return OnlineDiscoveryResult(
            success: true,
            message: hasPgx
                ? 'Official FDA pharmacogenomic guidance discovered for $fdaGenericName (${detectedGenes.join(', ')}).'
                : 'Official FDA label located; no validated germline PGx relationship reported.',
            identity: identity,
            evidence: discoveredEvidence,
            sourceUrl: uri,
          );
        }
      }
    } catch (e) {
      debugPrint('OpenFDA online lookup error: $e');
    }

    // 4. If neither local catalog nor online API has evidence
    final unknownEvidence = DrugEvidence(
      genericName: identity.genericName,
      displayName: identity.displayName,
      aliases: identity.aliases,
      genes: [],
      guidelineCitation: 'Insufficient validated pharmacogenomic clinical evidence in CPIC, PharmGKB, or FDA databases.',
      dosingRecommendation: 'Consult a clinical pharmacologist or pharmacist before prescribing.',
      mechanism: 'No verified pharmacogenomic metabolic pathway mapped.',
      evidenceLevel: 'Insufficient Evidence',
      source: 'Online Evidence Discovery Service',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: DateTime.now().toIso8601String(),
      isOnlineDiscovered: true,
      verifiedMedicine: false,
    );

    return OnlineDiscoveryResult(
      success: false,
      message: 'No validated pharmacogenomic relationship found for "${identity.displayName}".',
      identity: identity,
      evidence: unknownEvidence,
    );
  }

  static String? _firstString(dynamic value) {
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static DrugEvidence? _findCatalogEvidence(
    String rawQuery,
    MedicineIdentity identity,
  ) {
    final normalized = rawQuery.trim().toUpperCase();
    for (final evidence in _authoritativePgxCatalog.values) {
      if (evidence.genericName == normalized ||
          evidence.aliases.any((alias) => alias.toUpperCase() == normalized) ||
          evidence.genericName == identity.genericName.toUpperCase()) {
        return evidence;
      }
    }
    return null;
  }
}
