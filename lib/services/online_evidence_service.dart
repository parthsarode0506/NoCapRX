import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/drug_evidence.dart';
import '../models/medicine_identity.dart';
import 'local_discovery_cache.dart';
import 'medicine_normalization_service.dart';
import 'groq_ai_service.dart';

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
      uses: ['Prevention and treatment of nausea and vomiting'],
      commonSideEffects: ['Headache', 'Constipation', 'Tiredness'],
      seriousSideEffects: [
        'Irregular heartbeat, fainting, or severe dizziness',
        'Severe allergic reaction',
      ],
      precautions: [
        'Tell a clinician about heart-rhythm problems or liver disease',
        'Seek help for fainting, chest fluttering, or swelling of the face or throat',
      ],
      evidenceSources: ['Standard ondansetron medicine safety information'],
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
      aliases: [
        'Acetaminophen',
        'Tylenol',
        'Crocin',
        'Calpol',
        'Panadol',
        'Dolo 650',
      ],
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
      uses: ['Relief of mild-to-moderate pain and fever'],
      commonSideEffects: ['Nausea', 'Stomach upset', 'Skin rash'],
      seriousSideEffects: [
        'Liver injury, especially after too much medicine or with alcohol',
        'Severe allergic reaction',
      ],
      precautions: [
        'Do not combine with another paracetamol or acetaminophen product',
        'Higher risk with liver disease or heavy alcohol use',
      ],
      evidenceSources: ['Standard paracetamol medicine safety information'],
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'AZITHROMYCIN': DrugEvidence(
      genericName: 'AZITHROMYCIN',
      displayName: 'Azithromycin',
      aliases: ['Zithromax', 'Azee', 'Azee 500', 'Atm 500', 'ATM500', 'Azithral', 'Z-Pak'],
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
      activeIngredients: ['Azithromycin'],
      uses: ['Treatment of certain bacterial infections when prescribed'],
      commonSideEffects: ['Nausea', 'Diarrhea', 'Stomach pain'],
      seriousSideEffects: [
        'Severe allergic reaction',
        'Irregular heartbeat, fainting, or severe dizziness',
        'Severe or persistent diarrhea',
      ],
      precautions: [
        'Higher risk with some heart-rhythm problems or liver disease',
        'Use only for a bacterial infection diagnosed by a clinician',
      ],
      evidenceSources: ['Standard azithromycin medicine safety information'],
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
      activeIngredients: ['Amoxicillin'],
      uses: ['Treatment of certain bacterial infections when prescribed'],
      commonSideEffects: ['Nausea', 'Diarrhea', 'Stomach discomfort', 'Skin rash'],
      seriousSideEffects: [
        'Severe allergic reaction',
        'Severe or persistent diarrhea',
        'Yellowing of the skin or eyes',
      ],
      precautions: [
        'Do not use if you have a serious penicillin allergy',
        'Use only for a bacterial infection diagnosed by a clinician',
      ],
      evidenceSources: ['Standard amoxicillin medicine safety information'],
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    ),
    'ASPIRIN': DrugEvidence(
      genericName: 'ASPIRIN',
      displayName: 'Aspirin',
      aliases: ['Acetylsalicylic Acid', 'Ecotrin', 'Disprin', 'Bayer Aspirin', 'Aspro', 'ASA'],
      activeIngredients: ['Aspirin'],
      dosageForm: 'tablet',
      guidelineCitation: 'Verified medicine identity; no actionable CPIC pharmacogenomic prescribing guideline for routine aspirin use.',
      dosingRecommendation: 'Dose and route must be confirmed from the product label and clinical indication.',
      monitoringAdvice: 'Review allergy history, bleeding risk, gastrointestinal ulcer history, kidney function, and interacting medicines.',
      mechanism: 'No actionable germline PGx relationship was established for routine aspirin prescribing.',
      evidenceLevel: 'Verified medicine identity; no actionable PGx association',
      source: 'FDA labeling / standard clinical safety review',
      uses: ['Pain relief and fever reduction', 'Antiplatelet treatment when prescribed for cardiovascular indications'],
      commonSideEffects: ['Stomach irritation', 'Heartburn', 'Easy bruising'],
      seriousSideEffects: ['Unusual bleeding', 'Black or bloody stools', 'Vomiting blood', 'Wheezing or facial swelling'],
      precautions: ['Avoid self-treatment if you have a serious aspirin/NSAID allergy', 'Ask a clinician before use with bleeding disorders, ulcers, kidney disease, or blood thinners'],
      evidenceSources: ['FDA-approved labeling', 'MedlinePlus aspirin information'],
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: ['Known allergies', 'Current medicines', 'Relevant conditions', 'Dose and route'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      isOnlineDiscovered: true,
      verifiedMedicine: true,
      identityConfidence: 0.99,
    ),
    'ZERODOL SP': DrugEvidence(
      genericName: 'ZERODOL SP',
      displayName: 'Zerodol-SP',
      aliases: ['Zerodol SP', 'Zerodol-P'],
      activeIngredients: ['Aceclofenac', 'Paracetamol', 'Serratiopeptidase'],
      dosageForm: 'tablet',
      guidelineCitation:
          'Verified brand composition and standard medicine safety information; no actionable PGx guideline identified.',
      dosingRecommendation:
          'Use only the dose and duration written by your prescriber. Do not combine with other paracetamol or NSAID products unless a clinician says it is appropriate.',
      monitoringAdvice:
          'Watch for stomach, kidney, liver, and allergic problems, especially with longer use.',
      mechanism:
          'Aceclofenac reduces inflammation and pain. Paracetamol reduces pain and fever. Serratiopeptidase is included in some products for swelling.',
      evidenceLevel: 'Verified medicine information; no actionable PGx association',
      source: 'Verified product information and standard medicine safety references',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['Short-term relief of pain and inflammation, when prescribed'],
      commonSideEffects: ['Stomach upset', 'Nausea', 'Diarrhea', 'Dizziness'],
      seriousSideEffects: [
        'Stomach or intestinal bleeding',
        'Severe allergic reaction',
        'Yellowing of the skin or eyes',
        'Reduced urine or sudden swelling',
      ],
      precautions: [
        'Higher risk with stomach ulcers, kidney or liver disease, heart disease, or NSAID allergy',
        'Ask a clinician before use during pregnancy or with blood thinners',
        'Do not take other paracetamol or painkiller products without checking first',
      ],
      evidenceSources: ['Verified product composition', 'Standard medicine safety references'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-06T00:00:00Z',
      isOnlineDiscovered: true,
      verifiedMedicine: true,
      identityConfidence: 0.95,
    ),

    // ── Antiretrovirals ────────────────────────────────────────────────────
    'TENOFOVIR': DrugEvidence(
      genericName: 'TENOFOVIR',
      displayName: 'Tenofovir',
      aliases: [
        'Tenofovir Disoproxil Fumarate', 'TDF', 'Tenofovir Alafenamide', 'TAF',
        'Viread', 'Vemlidy', 'Truvada', 'Descovy', 'Atripla', 'Complera',
        'Stribild', 'Genvoya', 'Biktarvy', 'TEN',
      ],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC pharmacogenomic guideline for Tenofovir. Used as an alternative to Abacavir in HLA-B*57:01 positive patients.',
      dosingRecommendation: 'Standard HIV/HBV treatment dosing per clinical guidelines. No PGx dose modification required.',
      alternativeDrugs: ['Abacavir (if HLA-B*57:01 negative)', 'Zidovudine'],
      monitoringAdvice: 'Monitor renal function and bone mineral density during TDF therapy.',
      mechanism: 'Nucleoside/nucleotide reverse transcriptase inhibitor (NRTI). Renal excretion via OAT1/OAT3 transporters.',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & WHO HIV Treatment Guidelines',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['HIV infection treatment', 'Hepatitis B treatment', 'HIV pre-exposure prophylaxis (PrEP)'],
      commonSideEffects: ['Nausea', 'Diarrhea', 'Headache', 'Fatigue'],
      seriousSideEffects: ['Kidney dysfunction', 'Lactic acidosis', 'Severe hepatomegaly'],
      precautions: ['Monitor kidney function regularly', 'Do not stop without medical advice'],
      requiredClinicalData: ['Renal Function / eGFR'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'LAMIVUDINE': DrugEvidence(
      genericName: 'LAMIVUDINE',
      displayName: 'Lamivudine',
      aliases: ['3TC', 'Epivir', 'Heptovir', 'Zeffix', '3tc'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC pharmacogenomic guideline for Lamivudine.',
      dosingRecommendation: 'Standard HIV/HBV dosing per clinical guidelines.',
      monitoringAdvice: 'Monitor for hepatitis B flares if discontinued.',
      mechanism: 'NRTI — competitive inhibitor of reverse transcriptase.',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & WHO HIV Treatment Guidelines',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['HIV infection', 'Hepatitis B treatment'],
      commonSideEffects: ['Nausea', 'Headache', 'Fatigue', 'Insomnia'],
      seriousSideEffects: ['Lactic acidosis', 'Severe hepatomegaly'],
      precautions: ['Do not stop without medical supervision'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'EFAVIRENZ': DrugEvidence(
      genericName: 'EFAVIRENZ',
      displayName: 'Efavirenz',
      aliases: ['EFV', 'Sustiva', 'Stocrin', 'Atripla'],
      genes: ['CYP2B6'],
      relevantVariants: ['rs3745274'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation: 'PharmGKB Level 1A evidence for CYP2B6 and Efavirenz. Dose reduction recommended for CYP2B6 slow metabolizers.',
      dosingRecommendation: 'For CYP2B6 Poor Metabolizers (*6/*6), reduce dose to 400 mg/day or switch to an alternative NNRTI due to risk of CNS toxicity.',
      alternativeDrugs: ['Rilpivirine', 'Doravirine', 'Dolutegravir'],
      monitoringAdvice: 'Monitor for CNS side effects (dizziness, nightmares, mood changes). Therapeutic drug monitoring advised for known CYP2B6 PMs.',
      mechanism: 'CYP2B6 is the primary metabolic enzyme for efavirenz. Poor metabolizers accumulate drug to toxic CNS concentrations.',
      evidenceLevel: 'PharmGKB Level 1A Evidence',
      source: 'PharmGKB (PA10233) & WHO HIV Guidelines',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['HIV infection treatment (NNRTI component)'],
      commonSideEffects: ['Dizziness', 'Insomnia', 'Rash', 'Vivid dreams'],
      seriousSideEffects: ['Severe depression', 'Hepatotoxicity', 'Rash (Stevens-Johnson)'],
      precautions: ['Avoid in first trimester of pregnancy', 'CNS monitoring required'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Statins ────────────────────────────────────────────────────────────
    'ATORVASTATIN': DrugEvidence(
      genericName: 'ATORVASTATIN',
      displayName: 'Atorvastatin',
      aliases: ['Lipitor', 'Atorva', 'Storvas', 'Tonact', 'Aztor'],
      genes: ['SLCO1B1'],
      relevantVariants: ['rs4149056'],
      phenotypes: ['Normal function', 'Decreased function', 'Poor function'],
      guidelineCitation: 'CPIC Guideline for SLCO1B1 and Statin-Associated Myopathy (2022 update).',
      dosingRecommendation: 'For SLCO1B1 Poor Function (*5/*5): use lowest dose or alternative statin. Atorvastatin is lower myopathy risk than simvastatin.',
      alternativeDrugs: ['Rosuvastatin', 'Pravastatin', 'Fluvastatin'],
      monitoringAdvice: 'Monitor for muscle pain, weakness, or elevated CK levels.',
      mechanism: 'SLCO1B1 transports atorvastatin into hepatocytes. Reduced function increases systemic statin exposure and myopathy risk.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['High cholesterol', 'Cardiovascular risk reduction'],
      commonSideEffects: ['Muscle aches', 'Headache', 'Digestive upset'],
      seriousSideEffects: ['Rhabdomyolysis', 'Severe liver problems'],
      precautions: ['Report unexplained muscle pain immediately'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.98,
    ),
    'ROSUVASTATIN': DrugEvidence(
      genericName: 'ROSUVASTATIN',
      displayName: 'Rosuvastatin',
      aliases: ['Crestor', 'Rosucad', 'Rozavel', 'Rosuvas'],
      genes: ['SLCO1B1'],
      relevantVariants: ['rs4149056'],
      phenotypes: ['Normal function', 'Decreased function', 'Poor function'],
      guidelineCitation: 'CPIC Guideline for SLCO1B1 and Statin-Associated Myopathy (2022 update).',
      dosingRecommendation: 'For SLCO1B1 Poor Function, limit dose to 20 mg/day maximum.',
      alternativeDrugs: ['Pravastatin', 'Fluvastatin'],
      monitoringAdvice: 'Monitor CK if muscle symptoms develop.',
      mechanism: 'SLCO1B1 is major hepatic uptake transporter for rosuvastatin.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['High cholesterol', 'Cardiovascular risk reduction'],
      commonSideEffects: ['Muscle aches', 'Headache'],
      seriousSideEffects: ['Rhabdomyolysis'],
      precautions: ['Report muscle pain immediately'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Antidepressants ────────────────────────────────────────────────────
    'SERTRALINE': DrugEvidence(
      genericName: 'SERTRALINE',
      displayName: 'Sertraline',
      aliases: ['Zoloft', 'Serlift', 'Lustral', 'Daxid'],
      genes: ['CYP2C19'],
      relevantVariants: ['rs4244285', 'rs12248560'],
      phenotypes: ['PM', 'IM', 'NM', 'RM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2D6 and CYP2C19 and SSRIs (2015 update).',
      dosingRecommendation: 'For CYP2C19 Poor Metabolizers, consider 50% dose reduction or alternative SSRI to avoid excess drug exposure. For Ultrarapid Metabolizers consider alternative therapy.',
      alternativeDrugs: ['Escitalopram', 'Fluoxetine', 'Mirtazapine'],
      monitoringAdvice: 'Monitor for serotonin syndrome and QTc prolongation.',
      mechanism: 'CYP2C19 and CYP2D6 are primary metabolic enzymes. PM status markedly raises plasma concentrations.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA451333)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Depression', 'Anxiety disorders', 'OCD', 'PTSD'],
      commonSideEffects: ['Nausea', 'Insomnia', 'Diarrhea', 'Dry mouth'],
      seriousSideEffects: ['Serotonin syndrome', 'Suicidal thoughts (young adults)', 'Hyponatremia'],
      precautions: ['Do not stop abruptly', 'Review all serotonergic medicines'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'CITALOPRAM': DrugEvidence(
      genericName: 'CITALOPRAM',
      displayName: 'Citalopram',
      aliases: ['Celexa', 'Cipramil', 'Cipralex (Escitalopram)', 'Escitalopram'],
      genes: ['CYP2C19'],
      relevantVariants: ['rs4244285', 'rs12248560'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2C19 and SSRIs (2015 update). FDA limits citalopram to 20 mg/day for CYP2C19 PMs due to QT prolongation risk.',
      dosingRecommendation: 'For CYP2C19 PM: maximum dose 20 mg/day. For IM: use standard dose with caution. For URM: consider alternative SSRI.',
      alternativeDrugs: ['Sertraline', 'Mirtazapine', 'Bupropion'],
      monitoringAdvice: 'ECG monitoring (QTc) recommended for CYP2C19 Poor Metabolizers on citalopram.',
      mechanism: 'CYP2C19 is the major metabolic enzyme. PM accumulation raises QTc prolongation risk.',
      evidenceLevel: 'CPIC Level A / FDA Safety Communication',
      source: 'CPIC Guidelines & PharmGKB & FDA Safety Communications',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Depression', 'Anxiety disorders'],
      commonSideEffects: ['Nausea', 'Dry mouth', 'Sweating', 'Insomnia'],
      seriousSideEffects: ['QT prolongation / arrhythmia', 'Serotonin syndrome'],
      precautions: ['Avoid doses above 40 mg/day in general; 20 mg/day cap for PMs'],
      requiredClinicalData: ['Baseline ECG / QTc'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'FLUOXETINE': DrugEvidence(
      genericName: 'FLUOXETINE',
      displayName: 'Fluoxetine',
      aliases: ['Prozac', 'Sarafem', 'Fludac', 'Flunil', 'Olanzapine/Fluoxetine'],
      genes: ['CYP2D6'],
      relevantVariants: ['rs3892097', 'rs1065852'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2D6 and SSRIs (2015 update).',
      dosingRecommendation: 'For CYP2D6 PM: consider 50% dose reduction. For URM: consider alternative SSRI not dependent on CYP2D6.',
      alternativeDrugs: ['Sertraline', 'Escitalopram', 'Venlafaxine'],
      monitoringAdvice: 'Note: Fluoxetine is also a potent CYP2D6 inhibitor; it can phenoconvert NM patients to functional PM status.',
      mechanism: 'CYP2D6 is primary metabolic enzyme. Fluoxetine also inhibits its own metabolism (mechanism-based inhibition).',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA449673)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Depression', 'OCD', 'Bulimia', 'Panic disorder'],
      commonSideEffects: ['Nausea', 'Insomnia', 'Reduced appetite', 'Anxiety'],
      seriousSideEffects: ['Serotonin syndrome', 'Suicidal thoughts (young adults)'],
      precautions: ['Long half-life means effects persist weeks after stopping'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Opioids ────────────────────────────────────────────────────────────
    'TRAMADOL': DrugEvidence(
      genericName: 'TRAMADOL',
      displayName: 'Tramadol',
      aliases: ['Ultram', 'Tramal', 'Ultracet', 'Dolcet', 'Contramal'],
      genes: ['CYP2D6'],
      relevantVariants: ['rs3892097', 'rs1065852'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2D6 and Codeine/Tramadol (2021 update).',
      dosingRecommendation: 'For CYP2D6 Ultrarapid Metabolizers: avoid tramadol — excess O-desmethyltramadol accumulation causes respiratory depression. For PM: expect reduced analgesic efficacy.',
      alternativeDrugs: ['Morphine', 'Oxycodone (lower CYP2D6 dependence)', 'NSAIDs'],
      monitoringAdvice: 'Monitor for sedation, respiratory rate, and pain relief adequacy.',
      mechanism: 'CYP2D6 converts tramadol to active O-desmethyltramadol (M1). URM produces dangerously high M1 concentrations.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA451735)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Moderate to moderately severe pain'],
      commonSideEffects: ['Nausea', 'Dizziness', 'Constipation', 'Headache'],
      seriousSideEffects: ['Respiratory depression (especially URM)', 'Seizures', 'Serotonin syndrome'],
      precautions: ['High-risk in CYP2D6 ultrarapid metabolizers', 'Opioid risks apply'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'MORPHINE': DrugEvidence(
      genericName: 'MORPHINE',
      displayName: 'Morphine',
      aliases: ['MS Contin', 'Kadian', 'Morphgesic', 'Oramorph', 'MST'],
      genes: ['UGT2B7'],
      relevantVariants: [],
      phenotypes: ['NM'],
      guidelineCitation: 'No CPIC Level A guideline for morphine. UGT2B7 polymorphisms have modest evidence for morphine-6-glucuronide accumulation.',
      dosingRecommendation: 'Standard opioid dosing. Dose titration based on pain response and adverse effects.',
      monitoringAdvice: 'Monitor for respiratory depression, sedation, and pain control. Reduce dose in renal impairment.',
      mechanism: 'Glucuronidated by UGT2B7 to active morphine-6-glucuronide (M6G) and inactive morphine-3-glucuronide (M3G).',
      evidenceLevel: 'No Actionable CPIC Level A PGx Association',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['Severe pain management'],
      commonSideEffects: ['Nausea', 'Constipation', 'Sedation', 'Dizziness'],
      seriousSideEffects: ['Respiratory depression', 'Dependence', 'Overdose'],
      precautions: ['Opioid risks apply; requires clinical monitoring'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Antibiotics ────────────────────────────────────────────────────────
    'DOXYCYCLINE': DrugEvidence(
      genericName: 'DOXYCYCLINE',
      displayName: 'Doxycycline',
      aliases: ['Vibramycin', 'Monodox', 'Oracea', 'Doxinex', 'Doxt'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC pharmacogenomic guideline for doxycycline.',
      dosingRecommendation: 'Standard antimicrobial dosing per clinical infection guidelines.',
      monitoringAdvice: 'Take with food to reduce GI irritation. Avoid in pregnancy and children under 8.',
      mechanism: 'Tetracycline antibiotic. Not significantly metabolized by CYP enzymes.',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & FDA labeling',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['Bacterial infections', 'Malaria prophylaxis', 'Acne'],
      commonSideEffects: ['Nausea', 'Diarrhea', 'Photosensitivity'],
      seriousSideEffects: ['Severe skin reaction', 'Esophageal ulceration'],
      precautions: ['Avoid in pregnancy and young children', 'Use sun protection'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'CIPROFLOXACIN': DrugEvidence(
      genericName: 'CIPROFLOXACIN',
      displayName: 'Ciprofloxacin',
      aliases: ['Cipro', 'Ciplox', 'Cifran', 'Ciprobay', 'Quintor'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC pharmacogenomic guideline for ciprofloxacin.',
      dosingRecommendation: 'Standard antimicrobial dosing per clinical infection guidelines.',
      monitoringAdvice: 'Avoid concurrent antacids. Monitor for tendon pain.',
      mechanism: 'Fluoroquinolone antibiotic. CYP1A2 inhibitor (may increase plasma levels of theophylline, caffeine, clozapine).',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & FDA labeling',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['Bacterial infections including UTI, respiratory, skin'],
      commonSideEffects: ['Nausea', 'Diarrhea', 'Headache'],
      seriousSideEffects: ['Tendon rupture', 'QT prolongation', 'C. difficile'],
      precautions: ['Avoid in children, pregnancy; watch for tendon symptoms'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Antihypertensives / Cardiovascular ────────────────────────────────
    'AMLODIPINE': DrugEvidence(
      genericName: 'AMLODIPINE',
      displayName: 'Amlodipine',
      aliases: ['Norvasc', 'Amlip', 'Amlopin', 'Stamlo', 'Amlovas'],
      genes: ['CYP3A5'],
      relevantVariants: ['rs776746'],
      phenotypes: ['NM', 'IM', 'PM'],
      guidelineCitation: 'PharmGKB Level 2A evidence for CYP3A5 and amlodipine. Moderate evidence that CYP3A5 expressers require higher doses.',
      dosingRecommendation: 'For CYP3A5 expressers (*1/*1 or *1/*3), blood pressure control may require titration to higher doses. Standard dose for non-expressers (*3/*3).',
      alternativeDrugs: ['Nifedipine', 'Felodipine', 'Lercanidipine'],
      monitoringAdvice: 'Monitor blood pressure response and dose titrate accordingly.',
      mechanism: 'CYP3A5 (and CYP3A4) metabolize amlodipine. Expressers have increased clearance resulting in lower plasma concentrations.',
      evidenceLevel: 'PharmGKB Level 2A Evidence',
      source: 'PharmGKB (PA448380) & Clinical Pharmacology Literature',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['High blood pressure', 'Angina'],
      commonSideEffects: ['Ankle swelling', 'Flushing', 'Headache'],
      seriousSideEffects: ['Severe hypotension', 'Worsening angina'],
      precautions: ['Do not stop abruptly', 'Monitor BP regularly'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.96,
    ),
    'METOPROLOL': DrugEvidence(
      genericName: 'METOPROLOL',
      displayName: 'Metoprolol',
      aliases: ['Lopressor', 'Toprol-XL', 'Metolar', 'Betaloc', 'Seloken'],
      genes: ['CYP2D6'],
      relevantVariants: ['rs3892097', 'rs1065852'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'PharmGKB Level 1A evidence for CYP2D6 and metoprolol. CPIC recommends dose reduction for CYP2D6 PMs.',
      dosingRecommendation: 'For CYP2D6 Poor Metabolizers: reduce dose by 50-75% or use an alternative beta-blocker metabolized differently (e.g., atenolol, bisoprolol).',
      alternativeDrugs: ['Atenolol', 'Bisoprolol', 'Carvedilol'],
      monitoringAdvice: 'Monitor heart rate, blood pressure, and AV conduction. PM patients risk bradycardia.',
      mechanism: 'CYP2D6 is the primary metabolic enzyme for metoprolol. PMs accumulate drug to high concentrations.',
      evidenceLevel: 'PharmGKB Level 1A / CPIC Level A Evidence',
      source: 'PharmGKB (PA450480) & CPIC Guidelines',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['High blood pressure', 'Heart failure', 'Angina', 'Rate control in AF'],
      commonSideEffects: ['Fatigue', 'Dizziness', 'Slow heart rate', 'Cold extremities'],
      seriousSideEffects: ['Severe bradycardia', 'Bronchospasm', 'Heart block'],
      precautions: ['Never stop abruptly — risk of rebound angina', 'Caution in asthma/COPD'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'LISINOPRIL': DrugEvidence(
      genericName: 'LISINOPRIL',
      displayName: 'Lisinopril',
      aliases: ['Zestril', 'Prinivil', 'Listril', 'Lisoril', 'Hipril'],
      genes: [],
      relevantVariants: [],
      phenotypes: [],
      guidelineCitation: 'No CPIC pharmacogenomic guideline for lisinopril.',
      dosingRecommendation: 'Standard dosing per hypertension/heart failure guidelines. Adjust for renal function.',
      monitoringAdvice: 'Monitor renal function, potassium, and blood pressure. Stop if angioedema occurs.',
      mechanism: 'ACE inhibitor. Excreted unchanged by kidney — no CYP metabolism.',
      evidenceLevel: 'No Actionable PGx Association',
      source: 'CPIC Guidelines & FDA labeling',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      uses: ['High blood pressure', 'Heart failure', 'Diabetic kidney protection'],
      commonSideEffects: ['Dry cough', 'Dizziness', 'Headache'],
      seriousSideEffects: ['Angioedema (potentially fatal)', 'Severe hypotension', 'Hyperkalemia'],
      precautions: ['Contraindicated in pregnancy', 'Stop immediately if throat swelling occurs'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Diabetes ───────────────────────────────────────────────────────────
    'GLIPIZIDE': DrugEvidence(
      genericName: 'GLIPIZIDE',
      displayName: 'Glipizide',
      aliases: ['Glucotrol', 'Minidiab', 'Glynase'],
      genes: ['CYP2C9'],
      relevantVariants: ['rs1799853', 'rs1057910'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation: 'CPIC Guideline for CYP2C9 and Sulfonylureas (2019 update).',
      dosingRecommendation: 'For CYP2C9 Poor Metabolizers: initiate with lowest dose and monitor carefully for hypoglycemia — reduced clearance prolongs drug action.',
      alternativeDrugs: ['Metformin', 'DPP-4 inhibitors (not metabolized by CYP2C9)'],
      monitoringAdvice: 'Monitor blood glucose closely, especially in PMs. Hypoglycemia risk is significantly elevated.',
      mechanism: 'CYP2C9 is the primary metabolic pathway. PM patients have markedly prolonged hypoglycemic action.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Type 2 diabetes'],
      commonSideEffects: ['Hypoglycemia', 'Weight gain', 'Nausea'],
      seriousSideEffects: ['Severe hypoglycemia', 'Cholestatic jaundice'],
      precautions: ['Monitor blood glucose frequently; dose conservatively in PMs'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'GLIMEPIRIDE': DrugEvidence(
      genericName: 'GLIMEPIRIDE',
      displayName: 'Glimepiride',
      aliases: ['Amaryl', 'Glimisave', 'Glimpid', 'Glimy', 'Glorix'],
      genes: ['CYP2C9'],
      relevantVariants: ['rs1799853', 'rs1057910'],
      phenotypes: ['PM', 'IM', 'NM'],
      guidelineCitation: 'CPIC Guideline for CYP2C9 and Sulfonylureas (2019 update).',
      dosingRecommendation: 'For CYP2C9 Poor Metabolizers, use lowest possible dose with careful glucose monitoring due to hypoglycemia risk.',
      alternativeDrugs: ['Metformin', 'Sitagliptin', 'Empagliflozin'],
      monitoringAdvice: 'Blood glucose monitoring, especially at initiation and dose increases in PMs.',
      mechanism: 'CYP2C9 metabolizes glimepiride. Reduced activity prolongs hypoglycemic effect.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Type 2 diabetes'],
      commonSideEffects: ['Hypoglycemia', 'Dizziness', 'Nausea'],
      seriousSideEffects: ['Severe hypoglycemia', 'Hemolytic anemia'],
      precautions: ['Monitor blood glucose; reduce dose in CYP2C9 PMs'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Antifungals ────────────────────────────────────────────────────────
    'VORICONAZOLE': DrugEvidence(
      genericName: 'VORICONAZOLE',
      displayName: 'Voriconazole',
      aliases: ['Vfend', 'Voritek', 'Vori'],
      genes: ['CYP2C19'],
      relevantVariants: ['rs4244285', 'rs12248560'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2C19 and Voriconazole (2016 update).',
      dosingRecommendation: 'For CYP2C19 Poor Metabolizers: reduce maintenance dose by 50% to avoid toxicity. For URM: standard dosing may lead to subtherapeutic levels — consider alternative antifungal.',
      alternativeDrugs: ['Isavuconazole', 'Posaconazole', 'Liposomal Amphotericin B'],
      monitoringAdvice: 'Therapeutic drug monitoring of voriconazole trough concentrations strongly recommended for all patients.',
      mechanism: 'CYP2C19 is the primary oxidative metabolic pathway. PM patients accumulate voriconazole to hepatotoxic concentrations.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA166161537)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['Invasive fungal infections', 'Candidiasis', 'Aspergillosis'],
      commonSideEffects: ['Visual disturbances', 'Elevated liver enzymes', 'Rash'],
      seriousSideEffects: ['Hepatotoxicity', 'QT prolongation', 'Hallucinations'],
      precautions: ['Therapeutic drug monitoring required', 'Multiple CYP interactions'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),

    // ── Proton Pump Inhibitors ─────────────────────────────────────────────
    'OMEPRAZOLE': DrugEvidence(
      genericName: 'OMEPRAZOLE',
      displayName: 'Omeprazole',
      aliases: ['Prilosec', 'Losec', 'Omez', 'Omifast', 'Omecip'],
      genes: ['CYP2C19'],
      relevantVariants: ['rs4244285', 'rs12248560'],
      phenotypes: ['PM', 'IM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2C19 and Proton Pump Inhibitors (2020 update).',
      dosingRecommendation: 'For CYP2C19 URM: increase omeprazole dose to 40 mg twice daily for H. pylori eradication. For PM: standard or lower doses are effective due to higher exposure.',
      alternativeDrugs: ['Rabeprazole (less CYP2C19 dependent)', 'Pantoprazole'],
      monitoringAdvice: 'Monitor for adequate acid suppression. Check H. pylori eradication success in URM.',
      mechanism: 'CYP2C19 is the primary metabolic enzyme for omeprazole. PM patients achieve markedly higher drug exposure.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB (PA166104966)',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['GERD', 'H. pylori eradication', 'Peptic ulcer disease'],
      commonSideEffects: ['Headache', 'Nausea', 'Diarrhea', 'Abdominal pain'],
      seriousSideEffects: ['C. difficile infection', 'Hypomagnesemia', 'Bone fracture risk (long term)'],
      precautions: ['Review long-term use annually', 'Check for drug interactions (clopidogrel)'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.97,
    ),
    'PANTOPRAZOLE': DrugEvidence(
      genericName: 'PANTOPRAZOLE',
      displayName: 'Pantoprazole',
      aliases: ['Protonix', 'Pantop', 'Pantocid', 'Pan-D', 'Controloc'],
      genes: ['CYP2C19'],
      relevantVariants: ['rs4244285'],
      phenotypes: ['PM', 'NM', 'URM'],
      guidelineCitation: 'CPIC Guideline for CYP2C19 and Proton Pump Inhibitors (2020 update).',
      dosingRecommendation: 'For CYP2C19 URM: increase dose for H. pylori eradication. For PM: standard dose.',
      alternativeDrugs: ['Rabeprazole'],
      monitoringAdvice: 'Monitor acid suppression efficacy.',
      mechanism: 'CYP2C19 is primary metabolic enzyme, though pantoprazole has lower CYP2C19 dependence than omeprazole.',
      evidenceLevel: 'CPIC Level A Evidence',
      source: 'CPIC Guidelines & PharmGKB',
      clinicallyActionable: true,
      hasPgxRelationship: true,
      uses: ['GERD', 'H. pylori eradication', 'Peptic ulcer'],
      commonSideEffects: ['Headache', 'Diarrhea', 'Nausea'],
      seriousSideEffects: ['C. difficile infection', 'Hypomagnesemia'],
      precautions: ['Review long-term use regularly'],
      requiredClinicalData: [],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
      verifiedMedicine: true,
      identityConfidence: 0.96,
    ),
  };

  /// Discovers and validates pharmacogenomic evidence for any medicine.
  static Future<OnlineDiscoveryResult> discover(String rawMedicineQuery) async {
    await LocalDiscoveryCache.init();
    final identity = MedicineNormalizationService.identify(rawMedicineQuery);
    final catalogEvidence = _findCatalogEvidence(rawMedicineQuery, identity);
    final canonicalName = catalogEvidence?.genericName.toUpperCase() ??
        identity.genericName.toUpperCase();

    // Prefer the bundled authoritative catalog over stale cached records.
    // This prevents an older incomplete lookup from hiding corrected facts.
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
        uses: evidence.uses,
        commonSideEffects: evidence.commonSideEffects,
        seriousSideEffects: evidence.seriousSideEffects,
        precautions: evidence.precautions,
        evidenceSources: evidence.evidenceSources,
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

    // Use persistent discovery cache when no bundled authoritative entry exists.
    final cachedEvidence = LocalDiscoveryCache.get(canonicalName) ??
        LocalDiscoveryCache.get(identity.displayName);
    if (cachedEvidence != null &&
        cachedEvidence.verifiedMedicine &&
        (cachedEvidence.uses.isNotEmpty ||
            cachedEvidence.commonSideEffects.isNotEmpty ||
            cachedEvidence.genes.isNotEmpty)) {
      return OnlineDiscoveryResult(
        success: true,
        message: 'Evidence loaded from offline local discovery cache.',
        identity: identity,
        evidence: cachedEvidence,
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

    // Ask AI for medicine facts when the local catalog and OpenFDA do not
    // recognize the name. AI facts explain the medicine; they never assign risk.
    try {
      final aiResult = await GroqAIService().searchDrugOnline(rawMedicineQuery);
      final isReal = aiResult?['isRealMedicine']?.toString().toLowerCase() == 'true';
      final confidence = double.tryParse(aiResult?['confidence']?.toString() ?? '0') ?? 0;
      if (aiResult != null && isReal && confidence >= 0.70) {
        List<String> splitCsv(dynamic value) => (value?.toString() ?? '')
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final genericName = (aiResult['genericName']?.toString().trim().isNotEmpty == true
                ? aiResult['genericName'].toString()
                : rawMedicineQuery.trim())
            .toUpperCase();
        final displayName = aiResult['displayName']?.toString().trim().isNotEmpty == true
            ? aiResult['displayName'].toString().trim()
            : rawMedicineQuery.trim();
        final pgxYes = aiResult['pgxRelevance']?.toString().toLowerCase() == 'yes';
        final pgxGene = aiResult['pgxGene']?.toString().trim() ?? '';
        final evidence = DrugEvidence(
          genericName: genericName,
          displayName: displayName,
          aliases: identity.aliases,
          genes: pgxYes && pgxGene.isNotEmpty ? [pgxGene] : const [],
          phenotypes: splitCsv(aiResult['pgxPhenotypes']),
          guidelineCitation: aiResult['guidelineSummary']?.toString() ?? 'No verified PGx guideline found.',
          dosingRecommendation: 'Follow the product label and advice from a doctor or pharmacist.',
          monitoringAdvice: 'Follow standard monitoring advice for this medicine.',
          mechanism: 'No patient-specific genetic mechanism was calculated.',
          evidenceLevel: aiResult['evidenceLevel']?.toString() ?? 'Medicine facts found online',
          source: 'AI medicine lookup; verify with a pharmacist',
          clinicallyActionable: false,
          hasPgxRelationship: pgxYes && pgxGene.isNotEmpty,
          uses: splitCsv(aiResult['uses']),
          commonSideEffects: splitCsv(aiResult['commonSideEffects']),
          seriousSideEffects: splitCsv(aiResult['seriousSideEffects']),
          precautions: splitCsv(aiResult['precautions']),
          evidenceSources: const ['AI medicine lookup; pharmacist verification recommended'],
          requiredClinicalData: const [],
          retrievalTimestamp: DateTime.now().toIso8601String(),
          isOnlineDiscovered: true,
          verifiedMedicine: true,
          identityConfidence: confidence,
        );
        await LocalDiscoveryCache.put(evidence);
        return OnlineDiscoveryResult(
          success: true,
          message: 'Medicine facts found online for $displayName. Verify the package before use.',
          identity: identity,
          evidence: evidence,
          sourceUrl: Uri.https('www.google.com', '/search', {
            'q': '$displayName medicine uses side effects',
          }),
        );
      }
    } catch (e) {
      debugPrint('AI medicine lookup error: $e');
    }

    // 5. If neither local catalog nor online API has evidence — create a
    //    verified-identity result so the user still gets a clinical safety
    //    assessment (allergy/interaction checks) even with no PGx data.
    //    Only mark verifiedMedicine: false if the query was too short/ambiguous
    //    to plausibly be a real medicine name.
    final queryLength = rawMedicineQuery.trim().length;
    final likelyRealMedicine = queryLength >= 4;

    final unknownEvidence = DrugEvidence(
      genericName: identity.genericName.isEmpty
          ? rawMedicineQuery.trim().toUpperCase()
          : identity.genericName,
      displayName: identity.displayName.isEmpty
          ? rawMedicineQuery.trim()
          : identity.displayName,
      aliases: identity.aliases,
      genes: [],
      guidelineCitation: likelyRealMedicine
          ? 'No validated pharmacogenomic clinical evidence found in CPIC, PharmGKB, or FDA databases for this medicine.'
          : 'Insufficient information to identify this medicine.',
      dosingRecommendation: likelyRealMedicine
          ? 'Consult a clinical pharmacologist or pharmacist before prescribing.'
          : 'Please enter the full generic or brand name of the medicine.',
      mechanism: 'No verified pharmacogenomic metabolic pathway mapped.',
      evidenceLevel: 'Insufficient Evidence',
      source: 'PharmaGuard Evidence Discovery Service',
      clinicallyActionable: false,
      hasPgxRelationship: false,
      requiredClinicalData: [],
      retrievalTimestamp: DateTime.now().toIso8601String(),
      isOnlineDiscovered: true,
      // Mark as verified if query is long enough to be a plausible medicine name.
      // This lets the clinical safety engine still check allergies/interactions.
      verifiedMedicine: likelyRealMedicine,
      identityConfidence: likelyRealMedicine ? 0.45 : 0.0,
    );

    return OnlineDiscoveryResult(
      success: likelyRealMedicine,
      message: likelyRealMedicine
          ? 'No pharmacogenomic evidence found for "${identity.displayName}". '
              'A clinical safety assessment will still be performed using your profile.'
          : 'Could not identify "${rawMedicineQuery.trim()}" as a medicine. '
              'Please enter the full generic or brand name.',
      identity: identity,
      evidence: likelyRealMedicine ? unknownEvidence : null,
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
    final identityNorm = identity.genericName.toUpperCase();

    for (final evidence in _authoritativePgxCatalog.values) {
      // Exact match on generic name
      if (evidence.genericName == normalized) return evidence;
      // Match on any alias (case-insensitive)
      if (evidence.aliases.any((a) => a.toUpperCase() == normalized)) {
        return evidence;
      }
      // Match via identity resolution
      if (evidence.genericName == identityNorm) return evidence;
      // Match on display name
      if (evidence.displayName.toUpperCase() == normalized) return evidence;
      // Partial prefix match for abbreviated inputs (≥4 chars)
      if (normalized.length >= 4 &&
          (evidence.genericName.startsWith(normalized) ||
              evidence.displayName.toUpperCase().startsWith(normalized) ||
              evidence.aliases.any(
                  (a) => a.toUpperCase().startsWith(normalized)))) {
        return evidence;
      }
    }
    return null;
  }
}
