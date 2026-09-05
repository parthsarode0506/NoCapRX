# PharmaGuard (NoCapRX) — App Concept

## 1. Problem
Different people respond differently to the same medicine, often due to genetic variation that affects metabolism, activation, exposure, adverse-event risk, or required dose. Traditional prescribing rarely incorporates this automatically. PharmaGuard makes pharmacogenomic (PGx) decision support accessible and understandable.

## 2. What the user does
1. Create an account.
2. Upload a genetic VCF file.
3. Enter a medicine name (e.g. *Clopidogrel*).
4. The app identifies the relevant gene(s) (e.g. *CYP2C19*).
5. The app extracts the relevant genetic information from the VCF **on the phone**.
6. If the clinical rule requires extra information (age, weight, etc.), the app asks only for that.
7. The deterministic PGx engine evaluates the information.
8. The user receives one of: 🟢 Safe, 🟡 Adjust Dosage, 🔴 Toxic, 🟠 Ineffective, ⚪ Unknown.
9. The user can tap **"Why?"** to understand the result.

## 3. "Any medicine" support
- **Case A — Known medicine**: local database → validated evidence → analyze.
- **Case B — Not local, but validated online evidence exists**: online search → validated evidence → analyze.
- **Case C — No sufficient evidence**: → **UNKNOWN — insufficient validated pharmacogenomic evidence**.

The system must never ask an AI model to *guess* safety.

## 4. Role of AI
- **AI does**: explain the result, explain the genetic mechanism, translate to plain language, answer questions about the generated report.
- **AI does NOT**: decide risk, change risk, invent variants/phenotypes/CPIC recommendations, prescribe, override the deterministic engine.

## 5. Evidence Chain
For every result: `Detected Variant → Gene → Star Allele → Diplotype → Phenotype → Medicine → Clinical Evidence → Risk Classification`.

## 6. What is a VCF?
Variant Call Format — a standard representation of genetic variants (chromosome, position, ref/alt allele, rsID, genotype). Parsed **locally**.

## 7. Initial pharmacogenomic coverage
| Gene     | Medicine      |
|----------|---------------|
| CYP2D6   | Codeine       |
| CYP2C19  | Clopidogrel   |
| CYP2C9   | Warfarin      |
| SLCO1B1  | Simvastatin   |
| TPMT     | Azathioprine  |
| DPYD     | Fluorouracil  |

Architecture must be expandable for additional gene–drug pairs.

## 8. Three cases for any medicine
See section 3. Never fabricate a Safe/Harmful result.

## 9. Privacy — core principle
**Raw genetic data never leaves the device.**

Architecture:

```
PHONE
 ├── VCF
 ├── Local VCF Parser
 ├── Local PGx Engine
 ├── Derived Report
 │     ├──► Firebase
 │     └──► AI explanation
Raw VCF ──X──► Cloud
Raw VCF ──X──► AI
```

UI badge: 🔒 Genomic Privacy — VCF processing ✓ On Device, Raw VCF uploaded 0 KB, Raw genetic data Never uploaded.

## 10. Phone-first (iQOO hackathon fit)
The phone performs the important work:
- VCF parsing
- Variant analysis
- PGx rule evaluation
- Risk calculation

A local/open-source model can power the explanation layer; Snapdragon NPU acceleration may be investigated — **do not claim NPU usage unless implemented and measured.**

## 11. Offline-first
Without internet the app still performs:
- VCF parsing, variant matching, diplotype inference, phenotype mapping, local PGx rules, risk calculation, cached explanations.

Internet is only needed for: online medicine discovery, live evidence retrieval, Gemini/live AI, Firebase sync, auth.

Demo: turn off internet → upload VCF → analyze a locally supported drug → result still works.

## 12. Chatbot — "Ask About This Result"
Scoped to the current report only. Refuses general medical questions with: *"I can only answer questions about your current PharmaGuard report."*

## 13. Result screen
Risk badge, confidence bar, gene, diplotype, phenotype, evidence checklist, and `WHY?` / `VIEW EVIDENCE` / `ASK ABOUT RESULT` actions.

## 14. Report (JSON)
Contains: patient, patient ID, medicine, timestamp, risk (label, confidence, severity), pharmacogenomic profile (gene, diplotype, phenotype, detected variants), clinical recommendation (guideline citation, dosing, alternatives, monitoring), AI explanation (summary, mechanism, patient-friendly text, clinician note), and quality metrics.

## 15. Evidence and sources
Prioritize: CPIC, PharmGKB, FDA pharmacogenomic information, recognized clinical PGx guidelines.
For online-discovered medicines, track: medicine, gene, variant, evidence source, guideline, evidence strength, retrieval time → auditable trail.

## 16. Synthetic demo patients
- **001** — Normal/reference profile (Safe pathway)
- **002** — Reduced-function profile (Adjusted-response pathway)
- **003** — Toxicity-relevant profile (High-risk pathway)
- **004** — Incomplete genetic information (Unknown pathway)

## 17. Technical architecture
```
Flutter
├── Authentication
├── Home
├── VCF Module (local parser)
├── Medicine Module (local DB + online discovery)
├── Pharmacogenomics Engine
│   ├── Variant matcher
│   ├── Star allele mapper
│   ├── Diplotype engine
│   ├── Phenotype engine
│   └── Deterministic rules
├── Evidence Engine (source validation + provenance)
├── AI Explanation (local model + Gemini fallback)
├── Report (JSON + PDF)
├── Chatbot
├── History
└── Privacy / Security
```

## 18. USP
> "PharmaGuard is an on-device pharmacogenomic decision-support system that lets a user enter a medicine, discovers the relevant pharmacogenomic evidence, analyzes the patient's genetic data locally, applies deterministic clinical rules, and uses AI to explain the result."

Strongest statement: **"AI doesn't make the decision. The pharmacogenomic rule engine makes the decision; AI explains it."**

## 19. iQOO hackathon alignment
| Judging area | PharmaGuard feature |
|--------------|---------------------|
| End Product — 30% | Complete phone-first drug-safety workflow |
| Novelty — 20% | On-device PGx analysis + online medicine discovery |
| Creative Phone Use — 15% | VCF processing and risk engine on the iQOO device |
| Technical Depth — 15% | VCF parsing + variant/diplotype/phenotype + deterministic rules |
| Office Kit — 10% | Phone-first development/demo workflow |
| Demo — 10% | Enter medicine → analyze → evidence chain → AI explanation |

## 30-second pitch
"PharmaGuard is a phone-first pharmacogenomic safety assistant. A user uploads their genetic VCF and enters the medicine they want to check. The app identifies the relevant pharmacogenomic evidence, extracts the required genetic information directly on the phone, and applies deterministic clinical rules to assess the patient's predicted drug response. If a medicine isn't in our local database, we search validated online pharmacogenomic sources. AI doesn't decide the medical result — it explains the result and its evidence in simple language. Most importantly, the raw genetic file never leaves the device."

**One sentence**: 🧬 Upload your genetics → 💊 enter a medicine → 📋 receive a transparent, evidence-backed risk assessment with an AI explanation you can trust.
