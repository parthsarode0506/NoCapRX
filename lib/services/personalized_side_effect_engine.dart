import '../models/drug_evidence.dart';
import '../models/personalized_side_effect_risk.dart';

/// Transforms generic medication side-effect profiles into individualized,
/// evidence-backed patient assessments based on verified labeling and patient factors.
class PersonalizedSideEffectEngine {
  static List<PersonalizedSideEffectRisk> evaluate(
    DrugEvidence evidence,
    Map<String, String> clinicalData,
  ) {
    final drug = evidence.genericName.toUpperCase();
    final allergies = (clinicalData['Known allergies'] ?? '').toLowerCase();
    final current = (clinicalData['Current medicines'] ?? '').toLowerCase();
    final conditions = (clinicalData['Relevant conditions'] ?? '').toLowerCase();
    final kidney = (clinicalData['Kidney function'] ?? '').toLowerCase();
    final liver = (clinicalData['Liver function'] ?? '').toLowerCase();
    final age = int.tryParse(clinicalData['Age'] ?? '');
    final pregnancy = (clinicalData['Pregnancy/breastfeeding'] ?? '').toLowerCase();

    final results = <PersonalizedSideEffectRisk>[];

    // Collect base side effects from curated profiles or evidence
    final effectsList = _getCuratedEffects(drug, evidence);

    for (final def in effectsList) {
      final factors = <String>[];

      // Match patient risk factors based on side effect type & medication
      if (def.isGIBleedingRisk) {
        if (conditions.contains('ulcer') || conditions.contains('bleeding') || conditions.contains('gastritis')) {
          factors.add('Reported ulcer or bleeding history');
        }
        if (current.contains('warfarin') || current.contains('apixaban') || current.contains('rivaroxaban') || current.contains('dabigatran')) {
          factors.add('Reported anticoagulant medicine');
        }
        if (current.contains('clopidogrel') || current.contains('plavix') || current.contains('aspirin')) {
          factors.add('Reported antiplatelet medicine');
        }
        if (age != null && age >= 65) {
          factors.add('Age 65 or older');
        }
        if (pregnancy.isNotEmpty && !pregnancy.contains('not') && !pregnancy.contains('none') && !pregnancy.contains('no')) {
          factors.add('Reported pregnancy status (elevated NSAID bleeding/fetal risk)');
        }
      }

      if (def.isRenalRisk) {
        if (kidney.contains('disease') || kidney.contains('impair') || conditions.contains('kidney')) {
          factors.add('Reported kidney disease or renal impairment');
        }
        if (age != null && age >= 65) {
          factors.add('Age 65 or older');
        }
        if (current.contains('lisinopril') || current.contains('losartan') || current.contains('diuretic')) {
          factors.add('Taking concurrent ACEi/ARB or diuretic');
        }
      }

      if (def.isAllergyRisk) {
        if (allergies.contains(drug.toLowerCase()) ||
            ((drug == 'ASPIRIN' || drug == 'IBUPROFEN') && (allergies.contains('nsaid') || allergies.contains('aspirin'))) ||
            (drug == 'AMOXICILLIN' && (allergies.contains('penicillin') || allergies.contains('beta-lactam')))) {
          factors.add('Reported allergy to this medicine or related ingredient');
        }
      }

      if (def.isHepaticRisk) {
        if (liver.contains('disease') || liver.contains('impair') || conditions.contains('liver')) {
          factors.add('Reported liver disease or hepatic impairment');
        }
      }

      if (def.isSedationRisk) {
        if (current.contains('benzodiazepine') || current.contains('lorazepam') || current.contains('diazepam') || current.contains('alprazolam') || current.contains('alcohol')) {
          factors.add('Reported concurrent sedative or CNS depressant medication');
        }
        if (conditions.contains('asthma') || conditions.contains('copd') || conditions.contains('sleep apnea')) {
          factors.add('Reported respiratory condition');
        }
      }

      if (def.isMuscleRisk) {
        if (age != null && age >= 65) {
          factors.add('Age 65 or older');
        }
        if (current.contains('amlodipine') || current.contains('diltiazem') || current.contains('clarithromycin')) {
          factors.add('Taking interacting CYP3A4-inhibiting medication');
        }
      }

      final String relevance;
      final String explanation;

      if (factors.isNotEmpty) {
        if (factors.any((f) => f.contains('allergy'))) {
          relevance = 'CRITICAL_CONCERN';
          explanation = 'Your profile contains an explicit allergy flag for this class: ${factors.join('; ')}. Medical consultation required before use.';
        } else {
          relevance = 'HIGHER_CONCERN';
          explanation = 'Your profile contains factors associated with increased risk for this side effect: ${factors.join('; ')}.';
        }
      } else if (clinicalData.isEmpty) {
        relevance = 'CANNOT_ASSESS';
        explanation = 'Assessment cannot be completed without patient clinical profile data.';
      } else {
        relevance = 'NO_SPECIFIC_RISK_FACTOR_IDENTIFIED';
        explanation = 'No corresponding risk factor was identified from the information provided. This does not guarantee the side effect cannot occur.';
      }

      results.add(PersonalizedSideEffectRisk(
        sideEffect: def.name,
        severity: def.severity,
        frequency: def.frequency,
        higherRiskGroups: def.higherRiskGroups,
        patientRiskFactors: factors,
        relevance: relevance,
        explanation: explanation,
        evidenceSources: def.evidenceSources.isNotEmpty
            ? def.evidenceSources
            : (evidence.evidenceSources.isNotEmpty ? evidence.evidenceSources : [evidence.source]),
      ));
    }

    return results;
  }

  static List<_SideEffectDefinition> _getCuratedEffects(String drug, DrugEvidence evidence) {
    final list = <_SideEffectDefinition>[];

    if (drug == 'IBUPROFEN' || drug == 'ASPIRIN') {
      list.addAll([
        const _SideEffectDefinition(
          name: 'Gastrointestinal Bleeding & Ulceration',
          severity: 'SERIOUS',
          frequency: 'Uncommon to Serious (~1-5%)',
          higherRiskGroups: [
            'People with previous ulcers or gastrointestinal bleeding',
            'People taking anticoagulant or antiplatelet medicines',
            'People aged 65 years or older',
            'Patients with history of heavy alcohol consumption',
          ],
          evidenceSources: ['FDA Boxed Warning for NSAIDs', 'CPIC NSAID Guidelines'],
          isGIBleedingRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Acute Kidney Injury & Fluid Retention',
          severity: 'SERIOUS',
          frequency: 'Warning Sign (~1-2%)',
          higherRiskGroups: [
            'People with pre-existing kidney disease or decreased renal function',
            'People taking concurrent ACE inhibitors, ARBs, or diuretics',
            'Dehydrated or elderly individuals',
          ],
          evidenceSources: ['KDIGO Clinical Guidelines', 'FDA Prescribing Monograph'],
          isRenalRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Severe Allergic & Bronchospasm Reactions',
          severity: 'EMERGENCY_WARNING_SIGNS',
          frequency: 'Rare (<0.1%)',
          higherRiskGroups: [
            'People with known aspirin/NSAID triad (asthma, nasal polyps, NSAID allergy)',
            'Patients with prior drug-induced urticaria or angioedema',
          ],
          evidenceSources: ['GINA Asthma Guidelines', 'Official Drug Labeling'],
          isAllergyRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Dyspepsia, Nausea & Mild Abdominal Pain',
          severity: 'COMMON',
          frequency: 'Common (10-20%)',
          higherRiskGroups: [
            'Patients taking medication without food',
            'Individuals with sensitive gastric mucosa',
          ],
          evidenceSources: ['FDA Patient Information'],
        ),
      ]);
    } else if (drug == 'WARFARIN') {
      list.addAll([
        const _SideEffectDefinition(
          name: 'Major Hemorrhage & Gastrointestinal Bleeding',
          severity: 'SERIOUS',
          frequency: 'Serious / Boxed Warning',
          higherRiskGroups: [
            'Patients with CYP2C9 or VKORC1 sensitive genotypes',
            'Patients taking interacting antiplatelets, NSAIDs, or antibiotics',
            'Patients aged 65 or older, or with previous major bleed history',
          ],
          evidenceSources: ['FDA Boxed Warning for Warfarin', 'CPIC Warfarin Guidelines'],
          isGIBleedingRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Easy Bruising, Petechiae & Epistaxis',
          severity: 'COMMON',
          frequency: 'Very Common (>10%)',
          higherRiskGroups: ['All anticoagulated patients'],
          evidenceSources: ['FDA Package Insert'],
        ),
      ]);
    } else if (drug == 'CODEINE') {
      list.addAll([
        const _SideEffectDefinition(
          name: 'Life-Threatening Respiratory Depression',
          severity: 'EMERGENCY_WARNING_SIGNS',
          frequency: 'Serious / Black Box Warning',
          higherRiskGroups: [
            'CYP2D6 Ultra-rapid Metabolizers (rapid conversion to morphine)',
            'Patients taking concurrent benzodiazepines, sedatives, or alcohol',
            'Patients with obstructive sleep apnea, asthma, or COPD',
            'Children following tonsillectomy/adenoidectomy',
          ],
          evidenceSources: ['FDA Boxed Warning', 'CPIC CYP2D6 Codeine Guidelines'],
          isSedationRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Constipation, Somnolence & Dizziness',
          severity: 'COMMON',
          frequency: 'Common (>10%)',
          higherRiskGroups: ['Elderly patients', 'Immobilized individuals'],
          evidenceSources: ['FDA Product Monograph'],
        ),
      ]);
    } else if (drug == 'SIMVASTATIN' || drug == 'ATORVASTATIN') {
      list.addAll([
        const _SideEffectDefinition(
          name: 'Myopathy & Rhabdomyolysis',
          severity: 'SERIOUS',
          frequency: 'Serious / Warning Sign (<1%)',
          higherRiskGroups: [
            'SLCO1B1 *5 or 521T>C variant carriers (impaired hepatic statin uptake)',
            'Patients taking concurrent CYP3A4 inhibitors (Amlodipine, Clarithromycin, Diltiazem)',
            'Patients aged 65 or older, or with renal impairment',
          ],
          evidenceSources: ['CPIC Statin Guidelines', 'FDA Safety Communication'],
          isMuscleRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Mild Muscle Aches (Myalgia) & Headache',
          severity: 'COMMON',
          frequency: 'Common (2-10%)',
          higherRiskGroups: ['High intensity statin dosages'],
          evidenceSources: ['AHA/ACC Statin Guidance'],
        ),
      ]);
    } else if (drug == 'PARACETAMOL') {
      list.addAll([
        const _SideEffectDefinition(
          name: 'Acute Hepatic Injury & Hepatotoxicity',
          severity: 'SERIOUS',
          frequency: 'Serious / Overdose Warning',
          higherRiskGroups: [
            'Patients with pre-existing hepatic disease or cirrhosis',
            'Chronic alcohol users (>3 drinks/day)',
            'Malnourished or fasting individuals',
            'Doses exceeding 4,000 mg/day',
          ],
          evidenceSources: ['FDA Acetaminophen Black Box Warning'],
          isHepaticRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Nausea, Rash, or Headache',
          severity: 'COMMON',
          frequency: 'Rare at therapeutic doses (<1%)',
          higherRiskGroups: ['Patients with hypersensitivity'],
          evidenceSources: ['FDA Patient Guide'],
        ),
      ]);
    } else if (drug == 'AMOXICILLIN') {
      list.addAll([
        const _SideEffectDefinition(
          name: 'Severe Allergic Anaphylaxis & Cutaneous Reactions',
          severity: 'EMERGENCY_WARNING_SIGNS',
          frequency: 'Serious / Hypersensitivity Warning (<0.05%)',
          higherRiskGroups: [
            'Patients with personal or family history of penicillin allergy',
            'Patients with multiple drug allergies',
          ],
          evidenceSources: ['FDA Amoxicillin Package Monograph'],
          isAllergyRisk: true,
        ),
        const _SideEffectDefinition(
          name: 'Diarrhea, Nausea & Abdominal Discomfort',
          severity: 'COMMON',
          frequency: 'Common (5-10%)',
          higherRiskGroups: ['Patients on broad-spectrum antibiotics'],
          evidenceSources: ['Clinical Antimicrobial Guidelines'],
        ),
      ]);
    } else {
      // Dynamic fallback based on evidence provided in DrugEvidence
      for (final effect in evidence.commonSideEffects) {
        list.add(_SideEffectDefinition(
          name: effect,
          severity: 'COMMON',
          frequency: 'Common',
          higherRiskGroups: const ['General patient population'],
          evidenceSources: evidence.evidenceSources.isNotEmpty ? evidence.evidenceSources : [evidence.source],
        ));
      }
      for (final effect in evidence.seriousSideEffects) {
        final isBleed = effect.toLowerCase().contains('bleed') || effect.toLowerCase().contains('ulcer');
        final isRenal = effect.toLowerCase().contains('kidney') || effect.toLowerCase().contains('renal');
        final isAllergic = effect.toLowerCase().contains('allerg') || effect.toLowerCase().contains('anaphylaxis');
        final isHep = effect.toLowerCase().contains('liver') || effect.toLowerCase().contains('hepat');
        list.add(_SideEffectDefinition(
          name: effect,
          severity: 'SERIOUS',
          frequency: 'Serious / Warning Sign',
          higherRiskGroups: const [
            'People with relevant medical conditions or interacting medicines identified in labeling'
          ],
          evidenceSources: evidence.evidenceSources.isNotEmpty ? evidence.evidenceSources : [evidence.source],
          isGIBleedingRisk: isBleed,
          isRenalRisk: isRenal,
          isAllergyRisk: isAllergic,
          isHepaticRisk: isHep,
        ));
      }
    }

    return list;
  }
}

class _SideEffectDefinition {
  final String name;
  final String severity;
  final String frequency;
  final List<String> higherRiskGroups;
  final List<String> evidenceSources;
  final bool isGIBleedingRisk;
  final bool isRenalRisk;
  final bool isAllergyRisk;
  final bool isHepaticRisk;
  final bool isSedationRisk;
  final bool isMuscleRisk;

  const _SideEffectDefinition({
    required this.name,
    required this.severity,
    required this.frequency,
    required this.higherRiskGroups,
    this.evidenceSources = const [],
    this.isGIBleedingRisk = false,
    this.isRenalRisk = false,
    this.isAllergyRisk = false,
    this.isHepaticRisk = false,
    this.isSedationRisk = false,
    this.isMuscleRisk = false,
  });
}
