# PharmaGuard (OnDeviceRx)

**PharmaGuard (OnDeviceRx)** is an on-device pharmacogenomic risk prediction system built with Flutter for the RIFT / iQOO Hackathon tracks. 

It parses patient `.VCF` genetic files locally on-device, cross-references 6 target pharmacogenomic genes against 6 drugs using CPIC clinical guidelines, predicts drug-specific risk using an on-device deterministic rule engine, generates LLM-based clinical explanations (via Google Gemini API), and provides a report-grounded AI chatbot.

> 🔒 **Privacy Guarantee**: Raw genetic VCF file data **NEVER** leaves the user's device. Only derived JSON reports sync to Firebase Firestore.

---

## 🛠️ Tech Stack & Architecture

- **Framework**: Flutter (Dart, null-safety, Material 3 design)
- **State Management**: Flutter Riverpod (`flutter_riverpod`)
- **Backend & Auth**: Firebase Core, Firebase Auth (Email/Password + Google Sign-In), Cloud Firestore, Firebase Analytics, Firebase Crashlytics, Firebase App Check
- **On-Device VCF Parser**: Custom regex & VCF v4.2 header/data line parser (`lib/parser/vcf_parser.dart`)
- **Clinical Rule Engine**: Static CPIC deterministic rule table (`lib/rules_engine/cpic_rule_engine.dart`)
- **LLM Integration**: Google Gemini API via `http` (`lib/services/llm_service.dart`) with pre-bundled local asset fallback (`assets/data/bundled_explanations.json`) for 100% offline functionality
- **Export & Share**: PDF generation (`pdf`, `printing`) & native OS sharing (`share_plus`)

---

## 🧬 Supported Genes & Drugs Panel

| Target Gene | Primary Drug | Phenotypes Covered | CPIC Guidelines |
|---|---|---|---|
| **CYP2D6** | CODEINE | PM, IM, NM, RM, URM | CPIC Guideline for CYP2D6 and Codeine |
| **CYP2C19** | CLOPIDOGREL | PM, IM, NM, RM, URM | CPIC Guideline for CYP2C19 and Clopidogrel |
| **CYP2C9** | WARFARIN | PM, IM, NM | CPIC Guideline for CYP2C9 and Warfarin |
| **SLCO1B1** | SIMVASTATIN | Normal, Decreased, Poor function | CPIC Guideline for SLCO1B1 and Simvastatin |
| **TPMT** | AZATHIOPRINE | PM, IM, NM | CPIC Guideline for TPMT and Thiopurines |
| **DPYD** | FLUOROURACIL | PM, IM, NM | CPIC Guideline for DPYD and Fluoropyrimidines |

---

## 🚀 Setup & Installation Instructions

### 1. Environment Configuration (`.env`)
Create a `.env` file in the project root directory (copied from `.env.example`):
```bash
GEMINI_API_KEY=your_actual_gemini_api_key_here
```
*Note: If no API key is supplied or if offline, PharmaGuard keeps the deterministic medication analysis available and shows a clear AI-unavailable message.*

### 2. Firebase Configuration
1. Register an Android/iOS app in your [Firebase Console](https://console.firebase.google.com/).
2. Download and place `google-services.json` under `android/app/`.
3. Download and place `GoogleService-Info.plist` under `ios/Runner/`.
4. Deploy the included `firestore.rules` to your Firebase project:
```bash
firebase deploy --only firestore:rules
```

### 3. Run the Flutter App
```bash
# Get dependencies
flutter pub get

# Run on connected Android device/emulator
flutter run
```

---


---

## 📜 Output JSON Contract Schema

Reports produced by PharmaGuard match the required hackathon JSON schema:
```json
{
  "patient_id": "PATIENT_001",
  "drug": "CODEINE",
  "timestamp": "2026-09-04T12:00:00.000Z",
  "risk_assessment": {
    "risk_label": "Ineffective",
    "confidence_score": 0.95,
    "severity": "high"
  },
  "pharmacogenomic_profile": {
    "primary_gene": "CYP2D6",
    "diplotype": "*4/*4",
    "phenotype": "PM",
    "detected_variants": [ { "rsid": "rs3892097" } ]
  },
  "clinical_recommendation": {
    "cpic_guideline_citation": "CPIC Guideline for CYP2D6 and Codeine Therapy (2021 update).",
    "dosing_recommendation": "Avoid codeine use due to lack of efficacy.",
    "alternative_drugs": [ "Morphine", "Acetaminophen", "NSAIDs" ],
    "monitoring_advice": "Monitor pain scores closely and prescribe non-CYP2D6 analgesics."
  },
  "llm_generated_explanation": {
    "summary": "CYP2D6 Poor Metabolizer (PM): Severe lack of Codeine bioactivation.",
    "mechanism": "CYP2D6 is absent or non-functional (*4/*4 diplotype).",
    "patient_friendly": "Your body cannot convert Codeine into its active pain-relieving form.",
    "clinician_note": "CYP2D6 PM phenotype identified. Avoid codeine use due to lack of efficacy."
  },
  "quality_metrics": {
    "vcf_parsing_success": true,
    "variants_detected": 7,
    "genes_covered": [ "CYP2D6", "CYP2C19", "CYP2C9", "SLCO1B1", "TPMT", "DPYD" ],
    "diplotype_inferred": false,
    "annotation_completeness": 1.0
  }
}
```
