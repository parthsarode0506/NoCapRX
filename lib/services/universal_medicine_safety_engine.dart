class ClinicalSafetyFinding {
  final String status;
  final String title;
  final String explanation;
  final String evidenceSource;
  final String? interactingDrug;

  const ClinicalSafetyFinding({
    required this.status,
    required this.title,
    required this.explanation,
    required this.evidenceSource,
    this.interactingDrug,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'title': title,
        'explanation': explanation,
        'evidence_source': evidenceSource,
        if (interactingDrug != null) 'interacting_drug': interactingDrug,
      };
}

/// Conservative, deterministic safety and interaction checks backed by official FDA/CPIC warnings.
/// Absence of a finding is not a guarantee of safety and must never be treated as one.
class UniversalMedicineSafetyEngine {
  /// Evaluates the highest priority finding for backward compatibility with CPIC rule engine.
  static ClinicalSafetyFinding? evaluate(
    String medicine,
    Map<String, String>? clinicalData,
  ) {
    final findings = evaluateAll(medicine, clinicalData);
    if (findings.isEmpty) return null;

    // Prioritize CONTRAINDICATED / Allergy over DRUG_INTERACTION over USE_WITH_CAUTION
    for (final f in findings) {
      if (f.status == 'CONTRAINDICATED' || f.status == 'ALLERGY_CONCERN') {
        return f;
      }
    }
    for (final f in findings) {
      if (f.status == 'DRUG_INTERACTION_DETECTED' || f.status == 'HIGH_RISK_FINDING') {
        return f;
      }
    }
    return findings.first;
  }

  /// Evaluates all clinical findings (allergies, drug interactions, disease contraindications).
  static List<ClinicalSafetyFinding> evaluateAll(
    String medicine,
    Map<String, String>? clinicalData,
  ) {
    if (clinicalData == null || clinicalData.isEmpty) return const [];
    final findings = <ClinicalSafetyFinding>[];

    final drug = medicine.toUpperCase();
    final allergies = (clinicalData['Known allergies'] ?? '').toLowerCase();
    final current = (clinicalData['Current medicines'] ?? '').toLowerCase();
    final conditions = (clinicalData['Relevant conditions'] ?? '').toLowerCase();
    final kidney = (clinicalData['Kidney function'] ?? '').toLowerCase();
    final liver = (clinicalData['Liver function'] ?? '').toLowerCase();
    final pregnancy = (clinicalData['Pregnancy/breastfeeding'] ?? '').toLowerCase();

    // 1. ALLERGY CHECKS
    final isAspirinLike = drug == 'ASPIRIN' || drug == 'IBUPROFEN' || drug == 'CELECOXIB';
    if (isAspirinLike && (allergies.contains('aspirin') || allergies.contains('nsaid') || allergies.contains('ibuprofen'))) {
      findings.add(ClinicalSafetyFinding(
        status: 'CONTRAINDICATED',
        title: 'Reported NSAID / Aspirin Allergy',
        explanation: 'Your profile reports an allergy to aspirin or NSAID medications. $medicine is in this class and may trigger severe hypersensitivity or bronchospasm.',
        evidenceSource: 'FDA Package Insert Contraindications & Black Box Warnings',
      ));
    } else if (drug == 'AMOXICILLIN' && (allergies.contains('penicillin') || allergies.contains('amoxicillin') || allergies.contains('beta-lactam'))) {
      findings.add(ClinicalSafetyFinding(
        status: 'CONTRAINDICATED',
        title: 'Reported Penicillin / Beta-Lactam Allergy',
        explanation: 'Your profile reports an allergy to penicillin or beta-lactams. $medicine is a penicillin-class antibiotic with cross-reactivity.',
        evidenceSource: 'FDA Product Labeling / Recognized Allergy Precautions',
      ));
    } else if ((drug == 'CELECOXIB' || drug.contains('SULFA')) && allergies.contains('sulfa')) {
      findings.add(ClinicalSafetyFinding(
        status: 'CONTRAINDICATED',
        title: 'Reported Sulfonamide Allergy',
        explanation: '$medicine contains a sulfonamide moiety. Severe cutaneous hypersensitivity has been reported in patients with known sulfa allergies.',
        evidenceSource: 'FDA Approved Package Monograph',
      ));
    } else if (allergies.contains(drug.toLowerCase()) && drug.length > 3) {
      findings.add(ClinicalSafetyFinding(
        status: 'CONTRAINDICATED',
        title: 'Reported Medicine Allergy',
        explanation: 'Your profile explicitly lists an allergy matching $medicine. Do not take this medication without clinician guidance.',
        evidenceSource: 'Patient Reported Allergy Profile',
      ));
    }

    // 2. DRUG-DRUG INTERACTIONS
    if (drug == 'ASPIRIN' || drug == 'IBUPROFEN' || drug == 'CELECOXIB') {
      if (current.contains('warfarin')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'DRUG_INTERACTION_DETECTED',
          title: 'Anticoagulant Interaction (Warfarin)',
          explanation: 'Concurrent use of NSAIDs/Aspirin with Warfarin significantly elevates the risk of severe gastrointestinal hemorrhage and bleeding.',
          evidenceSource: 'CPIC / FDA Co-administration Interaction Warnings',
          interactingDrug: 'Warfarin',
        ));
      }
      if (current.contains('apixaban') || current.contains('rivaroxaban') || current.contains('dabigatran')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'DRUG_INTERACTION_DETECTED',
          title: 'Direct Oral Anticoagulant (DOAC) Interaction',
          explanation: 'Co-administration with DOACs produces additive inhibition of hemostasis, multiplying major bleeding hazards.',
          evidenceSource: 'FDA Black Box Warnings & Clinical Pharmacokinetics',
          interactingDrug: 'DOAC Anticoagulant',
        ));
      }
      if (current.contains('clopidogrel') || current.contains('plavix') || current.contains('ticagrelor')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'DRUG_INTERACTION_DETECTED',
          title: 'Dual Antiplatelet Bleeding Risk',
          explanation: 'Combining multiple antiplatelet agents or NSAIDs impairs platelet aggregation and increases ulceration risks.',
          evidenceSource: 'AHA/ACC Pharmacotherapy Guidelines',
          interactingDrug: 'Clopidogrel / Antiplatelet',
        ));
      }
      if (current.contains('methotrexate')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'DRUG_INTERACTION_DETECTED',
          title: 'Methotrexate Toxicity Risk',
          explanation: 'NSAIDs reduce tubular secretion of methotrexate, potentially precipitating severe bone marrow suppression and nephrotoxicity.',
          evidenceSource: 'FDA Prescribing Information / Boxed Warnings',
          interactingDrug: 'Methotrexate',
        ));
      }
    }

    if (drug == 'SIMVASTATIN' || drug == 'ATORVASTATIN') {
      if (current.contains('amlodipine') || current.contains('diltiazem') || current.contains('verapamil')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'DRUG_INTERACTION_DETECTED',
          title: 'CYP3A4 Statin Interaction (Calcium Channel Blocker)',
          explanation: 'Calcium channel blockers inhibit CYP3A4-mediated statin clearance, increasing systemic exposure and risk of myopathy or rhabdomyolysis.',
          evidenceSource: 'FDA Safety Alerts & Labeling Updates',
          interactingDrug: 'Calcium Channel Blocker',
        ));
      }
      if (current.contains('clarithromycin') || current.contains('erythromycin') || current.contains('itraconazole') || current.contains('ketoconazole')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'CONTRAINDICATED',
          title: 'Strong CYP3A4 Inhibitor Contraindication',
          explanation: 'Strong CYP3A4 inhibitors cause marked statin plasma concentration elevation. Concomitant simvastatin use is contraindicated.',
          evidenceSource: 'FDA Statin Package Insert Contraindications',
          interactingDrug: 'Strong CYP3A4 Inhibitor',
        ));
      }
    }

    if (drug == 'CODEINE') {
      if (current.contains('lorazepam') || current.contains('diazepam') || current.contains('alprazolam') || current.contains('clonazepam') || current.contains('benzodiazepine')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'CONTRAINDICATED',
          title: 'Opioid & Benzodiazepine Co-administration Warning',
          explanation: 'Concomitant use of opioids with benzodiazepines or other CNS depressants may result in profound sedation, respiratory depression, coma, and death.',
          evidenceSource: 'FDA Black Box Warning for Concomitant Opioid and Benzodiazepine Use',
          interactingDrug: 'Benzodiazepine',
        ));
      }
    }

    // 3. MEDICAL CONDITION WARNINGS & CONTRAINDICATIONS
    if (drug == 'ASPIRIN' || drug == 'IBUPROFEN' || drug == 'CELECOXIB') {
      if (conditions.contains('ulcer') || conditions.contains('bleeding') || conditions.contains('gastritis')) {
        findings.add(ClinicalSafetyFinding(
          status: 'USE_WITH_CAUTION',
          title: 'Peptic Ulcer or GI Bleeding History',
          explanation: '$medicine inhibits protective prostaglandins in the gastric mucosa, substantially aggravating ulceration and bleeding risks.',
          evidenceSource: 'FDA Black Box Warning for Gastrointestinal Toxicity',
        ));
      }
      if (conditions.contains('asthma')) {
        findings.add(ClinicalSafetyFinding(
          status: 'USE_WITH_CAUTION',
          title: 'Asthma / Bronchospasm Precaution',
          explanation: 'Patients with asthma may experience aspirin-exacerbated respiratory disease (AERD) with severe bronchospasm when taking NSAIDs.',
          evidenceSource: 'Global Initiative for Asthma (GINA) Clinical Guidelines',
        ));
      }
      if (kidney.contains('disease') || kidney.contains('impair') || kidney.contains('moderate') || kidney.contains('severe') || conditions.contains('kidney')) {
        findings.add(ClinicalSafetyFinding(
          status: 'USE_WITH_CAUTION',
          title: 'Renal Impairment Warning',
          explanation: 'NSAIDs reduce renal prostaglandins, decreasing renal blood flow and potentially inducing acute kidney injury in compromised kidneys.',
          evidenceSource: 'KDIGO Clinical Practice Guidelines for Kidney Health',
        ));
      }
    }

    if (drug == 'METFORMIN') {
      if (kidney.contains('severe') || kidney.contains('disease') || conditions.contains('kidney')) {
        findings.add(const ClinicalSafetyFinding(
          status: 'CONTRAINDICATED',
          title: 'Severe Renal Impairment Contraindication',
          explanation: 'Metformin is contraindicated in severe renal impairment (eGFR < 30 mL/min) due to danger of fatal lactic acidosis.',
          evidenceSource: 'FDA Metformin Prescribing Information & Boxed Warnings',
        ));
      }
    }

    if (pregnancy.isNotEmpty && !pregnancy.contains('not') && !pregnancy.contains('none') && !pregnancy.contains('no')) {
      if (drug == 'WARFARIN' || drug == 'SIMVASTATIN' || drug == 'ATORVASTATIN') {
        findings.add(ClinicalSafetyFinding(
          status: 'CONTRAINDICATED',
          title: 'Teratogenicity Warning in Pregnancy',
          explanation: '$medicine is contraindicated during pregnancy due to documented risks of fetal harm, birth defects, or pregnancy loss.',
          evidenceSource: 'FDA Pregnancy Category X / Teratogenicity Evidence',
        ));
      }
    }

    if (liver.contains('severe') || liver.contains('impair') || liver.contains('disease') || conditions.contains('liver') || conditions.contains('cirrhosis')) {
      if (drug == 'PARACETAMOL') {
        findings.add(const ClinicalSafetyFinding(
          status: 'USE_WITH_CAUTION',
          title: 'Hepatic Impairment Precaution',
          explanation: 'Reduced glutathione stores in impaired liver function increase susceptibility to acetaminophen hepatotoxicity at lower thresholds.',
          evidenceSource: 'FDA Acetaminophen Hepatotoxicity Guidance',
        ));
      }
    }

    return findings;
  }

  /// Synthesizes the overall assessment label based on findings and PGx status.
  static String determineOverallStatus({
    required String pgxRiskLabel,
    required List<ClinicalSafetyFinding> clinicalFindings,
    required bool hasMissingData,
  }) {
    if (clinicalFindings.any((f) => f.status == 'CONTRAINDICATED')) {
      return 'Contraindication identified';
    }
    if (clinicalFindings.any((f) => f.status == 'DRUG_INTERACTION_DETECTED' || f.status == 'HIGH_RISK_FINDING')) {
      return 'High-risk finding';
    }
    if (pgxRiskLabel == 'Toxic') {
      return 'High-risk finding';
    }
    if (clinicalFindings.any((f) => f.status == 'USE_WITH_CAUTION') ||
        pgxRiskLabel == 'Adjust Dosage' ||
        pgxRiskLabel == 'Ineffective') {
      return 'Use with caution';
    }
    if (hasMissingData || pgxRiskLabel == 'Unknown') {
      return 'Additional medical review required';
    }
    return 'No major risk identified';
  }
}
