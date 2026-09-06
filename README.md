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

### Ask NOCAPRx on-device model

The isolated medicine chat feature uses `flutter_gemma: ^1.7.1` with
`flutter_gemma_mediapipe: ^1.0.5`. Place the 4-bit Gemma 3n E2B MediaPipe
model at `assets/models/gemma-3n-E2B-it-int4.task` and keep the file size and
checksum documented for the release artifact. The model is approximately
3.1 GB, so this repository intentionally does not include it. The app shows a
model-load failure instead of silently downloading it. The Android manifest
declares optional OpenCL libraries for the GPU backend; no Kotlin bridge is
required. The service requests GPU and logs that request; it does not claim NPU
execution.

The Groq fallback is never automatic. Supply `GROQ_API_KEY` using
`--dart-define=GROQ_API_KEY=...` (or the existing `.env` for local development)
and optionally `--dart-define=GROQ_MODEL=...`. The UI asks for confirmation
before making the request and sends only the question plus retrieved local
medicine facts. Do not commit a key or a model file.

### 1. Environment Configuration (`.env`)
Create a `.env` file in the project root directory (copied from `.env.example`):
```bash
OPENROUTER_API_KEY=your_actual_openrouter_api_key_here
OPENROUTER_OCR_MODEL=openai/gpt-image-2
```
Prescription scans use the configured OpenRouter vision model. If no OpenRouter key is supplied, scans use on-device ML Kit OCR instead. If the selected OpenRouter model does not accept image inputs, set `OPENROUTER_OCR_MODEL` to a vision-capable OpenRouter model.

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
