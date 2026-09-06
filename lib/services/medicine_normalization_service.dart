import '../models/medicine_identity.dart';

class MedicineNormalizationService {
  static final Map<String, _DrugEntry> _knownDictionary = {
    'CLOPIDOGREL': const _DrugEntry(
      genericName: 'CLOPIDOGREL',
      displayName: 'Clopidogrel',
      drugClass: 'Antiplatelet',
      aliases: ['Plavix', 'Clopivas', 'Deplatt', 'Iscover', 'Clopilet'],
    ),
    'CODEINE': const _DrugEntry(
      genericName: 'CODEINE',
      displayName: 'Codeine',
      drugClass: 'Opioid Analgesic',
      aliases: ['Codeine Phosphate', 'Tylenol #3', 'Tylenol 3', 'Codlin'],
    ),
    'WARFARIN': const _DrugEntry(
      genericName: 'WARFARIN',
      displayName: 'Warfarin',
      drugClass: 'Anticoagulant',
      aliases: ['Coumadin', 'Jantoven', 'Warf', 'Marevan'],
    ),
    'SIMVASTATIN': const _DrugEntry(
      genericName: 'SIMVASTATIN',
      displayName: 'Simvastatin',
      drugClass: 'Statin / HMG-CoA Reductase Inhibitor',
      aliases: ['Zocor', 'Simvotin', 'Simcard', 'Vytorin'],
    ),
    'AZATHIOPRINE': const _DrugEntry(
      genericName: 'AZATHIOPRINE',
      displayName: 'Azathioprine',
      drugClass: 'Thiopurine Immunosuppressant',
      aliases: ['Imuran', 'Azasan', 'Azapress'],
    ),
    'FLUOROURACIL': const _DrugEntry(
      genericName: 'FLUOROURACIL',
      displayName: 'Fluorouracil',
      drugClass: 'Fluoropyrimidine Chemotherapy',
      aliases: ['5-FU', '5 FU', 'Adrucil', 'Capecitabine', 'Xeloda', 'Efudex'],
    ),
    'TACROLIMUS': const _DrugEntry(
      genericName: 'TACROLIMUS',
      displayName: 'Tacrolimus',
      drugClass: 'Calcineurin Inhibitor Immunosuppressant',
      aliases: ['Prograf', 'Advagraf', 'Envarsus XR', 'Protopic'],
    ),
    'ABACAVIR': const _DrugEntry(
      genericName: 'ABACAVIR',
      displayName: 'Abacavir',
      drugClass: 'Antiretroviral NRTI',
      aliases: ['Ziagen', 'Epzicom', 'Triumeq', 'Trizivir'],
    ),
    'CARBAMAZEPINE': const _DrugEntry(
      genericName: 'CARBAMAZEPINE',
      displayName: 'Carbamazepine',
      drugClass: 'Anticonvulsant / Mood Stabilizer',
      aliases: ['Tegretol', 'Carbatrol', 'Equetro', 'Epitol', 'Mazepine'],
    ),
    'PHENYTOIN': const _DrugEntry(
      genericName: 'PHENYTOIN',
      displayName: 'Phenytoin',
      drugClass: 'Hydantoin Anticonvulsant',
      aliases: ['Dilantin', 'Phenytek', 'Epanutin'],
    ),
    'TAMOXIFEN': const _DrugEntry(
      genericName: 'TAMOXIFEN',
      displayName: 'Tamoxifen',
      drugClass: 'Selective Estrogen Receptor Modulator (SERM)',
      aliases: ['Nolvadex', 'Soltamox'],
    ),
    'ONDANSETRON': const _DrugEntry(
      genericName: 'ONDANSETRON',
      displayName: 'Ondansetron',
      drugClass: '5-HT3 Receptor Antagonist Antiemetic',
      aliases: ['Zofran', 'Zuplenz', 'Emeset'],
    ),
    'IRINOTECAN': const _DrugEntry(
      genericName: 'IRINOTECAN',
      displayName: 'Irinotecan',
      drugClass: 'Topoisomerase I Inhibitor',
      aliases: ['Camptosar', 'Onivyde'],
    ),
    'CELECOXIB': const _DrugEntry(
      genericName: 'CELECOXIB',
      displayName: 'Celecoxib',
      drugClass: 'COX-2 Selective NSAID',
      aliases: ['Celebrex', 'Cobix'],
    ),
    'AMITRIPTYLINE': const _DrugEntry(
      genericName: 'AMITRIPTYLINE',
      displayName: 'Amitriptyline',
      drugClass: 'Tricyclic Antidepressant (TCA)',
      aliases: ['Elavil', 'Endep', 'Tryptomer'],
    ),
    'AZITHROMYCIN': const _DrugEntry(
      genericName: 'AZITHROMYCIN',
      displayName: 'Azithromycin',
      drugClass: 'Macrolide Antibiotic',
      aliases: ['Zithromax', 'Azee', 'Azee 500', 'Atm 500', 'ATM500', 'Azithral', 'Z-Pak'],
    ),
    'PARACETAMOL': const _DrugEntry(
      genericName: 'PARACETAMOL',
      displayName: 'Paracetamol / Acetaminophen',
      drugClass: 'Analgesic & Antipyretic',
      aliases: [
        'Acetaminophen',
        'Tylenol',
        'Crocin',
        'Calpol',
        'Panadol',
        'Dolo 650',
      ],
    ),
    'IBUPROFEN': const _DrugEntry(
      genericName: 'IBUPROFEN',
      displayName: 'Ibuprofen',
      drugClass: 'NSAID',
      aliases: ['Advil', 'Motrin', 'Brufen', 'Nurofen'],
    ),
    'ASPIRIN': const _DrugEntry(
      genericName: 'ASPIRIN',
      displayName: 'Aspirin / Acetylsalicylic Acid',
      drugClass: 'NSAID & Antiplatelet',
      aliases: ['Acetylsalicylic Acid', 'Ecotrin', 'Disprin', 'Bayer Aspirin', 'Aspro'],
    ),
    'METFORMIN': const _DrugEntry(
      genericName: 'METFORMIN',
      displayName: 'Metformin',
      drugClass: 'Biguanide Antidiabetic',
      aliases: ['Glucophage', 'Fortamet', 'Glycomet', 'Riomet'],
    ),
    'ATORVASTATIN': const _DrugEntry(
      genericName: 'ATORVASTATIN',
      displayName: 'Atorvastatin',
      drugClass: 'Statin / HMG-CoA Reductase Inhibitor',
      aliases: ['Lipitor', 'Atorva', 'Storvas'],
    ),
    'AMOXICILLIN': const _DrugEntry(
      genericName: 'AMOXICILLIN',
      displayName: 'Amoxicillin',
      drugClass: 'Penicillin Antibiotic',
      aliases: ['Amoxil', 'Moxatag', 'Augmentin', 'Novamox'],
    ),
    // ── Antiretrovirals ────────────────────────────────────────────────────
    'TENOFOVIR': const _DrugEntry(
      genericName: 'TENOFOVIR',
      displayName: 'Tenofovir',
      drugClass: 'Antiretroviral NRTI',
      aliases: [
        'Tenofovir Disoproxil Fumarate', 'TDF', 'Tenofovir Alafenamide', 'TAF',
        'Viread', 'Vemlidy', 'Truvada', 'Descovy', 'Atripla', 'Complera',
        'Stribild', 'Genvoya', 'Biktarvy', 'TEN',
      ],
    ),
    'LAMIVUDINE': const _DrugEntry(
      genericName: 'LAMIVUDINE',
      displayName: 'Lamivudine',
      drugClass: 'Antiretroviral NRTI',
      aliases: ['3TC', 'Epivir', 'Heptovir', 'Zeffix', '3tc'],
    ),
    'EFAVIRENZ': const _DrugEntry(
      genericName: 'EFAVIRENZ',
      displayName: 'Efavirenz',
      drugClass: 'Antiretroviral NNRTI',
      aliases: ['EFV', 'Sustiva', 'Stocrin', 'Atripla'],
    ),
    // ── Antidepressants / Anxiolytics ──────────────────────────────────────
    'SERTRALINE': const _DrugEntry(
      genericName: 'SERTRALINE',
      displayName: 'Sertraline',
      drugClass: 'SSRI Antidepressant',
      aliases: ['Zoloft', 'Serlift', 'Lustral', 'Daxid'],
    ),
    'CITALOPRAM': const _DrugEntry(
      genericName: 'CITALOPRAM',
      displayName: 'Citalopram',
      drugClass: 'SSRI Antidepressant',
      aliases: ['Celexa', 'Cipramil'],
    ),
    'ESCITALOPRAM': const _DrugEntry(
      genericName: 'ESCITALOPRAM',
      displayName: 'Escitalopram',
      drugClass: 'SSRI Antidepressant',
      aliases: ['Cipralex', 'Lexapro', 'Nexito', 'Escitop'],
    ),
    'FLUOXETINE': const _DrugEntry(
      genericName: 'FLUOXETINE',
      displayName: 'Fluoxetine',
      drugClass: 'SSRI Antidepressant',
      aliases: ['Prozac', 'Sarafem', 'Fludac', 'Flunil'],
    ),
    // ── Opioids ────────────────────────────────────────────────────────────
    'TRAMADOL': const _DrugEntry(
      genericName: 'TRAMADOL',
      displayName: 'Tramadol',
      drugClass: 'Opioid Analgesic',
      aliases: ['Ultram', 'Tramal', 'Ultracet', 'Dolcet', 'Contramal'],
    ),
    'MORPHINE': const _DrugEntry(
      genericName: 'MORPHINE',
      displayName: 'Morphine',
      drugClass: 'Opioid Analgesic',
      aliases: ['MS Contin', 'Kadian', 'Morphgesic', 'Oramorph', 'MST'],
    ),
    // ── Statins ────────────────────────────────────────────────────────────
    'ROSUVASTATIN': const _DrugEntry(
      genericName: 'ROSUVASTATIN',
      displayName: 'Rosuvastatin',
      drugClass: 'Statin',
      aliases: ['Crestor', 'Rosucad', 'Rozavel', 'Rosuvas'],
    ),
    // ── Antihypertensives ─────────────────────────────────────────────────
    'AMLODIPINE': const _DrugEntry(
      genericName: 'AMLODIPINE',
      displayName: 'Amlodipine',
      drugClass: 'Calcium Channel Blocker',
      aliases: ['Norvasc', 'Amlip', 'Amlopin', 'Stamlo', 'Amlovas'],
    ),
    'METOPROLOL': const _DrugEntry(
      genericName: 'METOPROLOL',
      displayName: 'Metoprolol',
      drugClass: 'Beta-Blocker',
      aliases: ['Lopressor', 'Toprol-XL', 'Metolar', 'Betaloc', 'Seloken'],
    ),
    'LISINOPRIL': const _DrugEntry(
      genericName: 'LISINOPRIL',
      displayName: 'Lisinopril',
      drugClass: 'ACE Inhibitor',
      aliases: ['Zestril', 'Prinivil', 'Listril', 'Lisoril', 'Hipril'],
    ),
    // ── Antibiotics ───────────────────────────────────────────────────────
    'DOXYCYCLINE': const _DrugEntry(
      genericName: 'DOXYCYCLINE',
      displayName: 'Doxycycline',
      drugClass: 'Tetracycline Antibiotic',
      aliases: ['Vibramycin', 'Monodox', 'Oracea', 'Doxinex', 'Doxt'],
    ),
    'CIPROFLOXACIN': const _DrugEntry(
      genericName: 'CIPROFLOXACIN',
      displayName: 'Ciprofloxacin',
      drugClass: 'Fluoroquinolone Antibiotic',
      aliases: ['Cipro', 'Ciplox', 'Cifran', 'Ciprobay', 'Quintor'],
    ),
    // ── Antifungals ───────────────────────────────────────────────────────
    'VORICONAZOLE': const _DrugEntry(
      genericName: 'VORICONAZOLE',
      displayName: 'Voriconazole',
      drugClass: 'Triazole Antifungal',
      aliases: ['Vfend', 'Voritek', 'Vori'],
    ),
    // ── Diabetes ──────────────────────────────────────────────────────────
    'GLIPIZIDE': const _DrugEntry(
      genericName: 'GLIPIZIDE',
      displayName: 'Glipizide',
      drugClass: 'Sulfonylurea Antidiabetic',
      aliases: ['Glucotrol', 'Minidiab', 'Glynase'],
    ),
    'GLIMEPIRIDE': const _DrugEntry(
      genericName: 'GLIMEPIRIDE',
      displayName: 'Glimepiride',
      drugClass: 'Sulfonylurea Antidiabetic',
      aliases: ['Amaryl', 'Glimisave', 'Glimpid', 'Glimy', 'Glorix'],
    ),
    // ── PPIs ──────────────────────────────────────────────────────────────
    'OMEPRAZOLE': const _DrugEntry(
      genericName: 'OMEPRAZOLE',
      displayName: 'Omeprazole',
      drugClass: 'Proton Pump Inhibitor',
      aliases: ['Prilosec', 'Losec', 'Omez', 'Omifast', 'Omecip'],
    ),
    'PANTOPRAZOLE': const _DrugEntry(
      genericName: 'PANTOPRAZOLE',
      displayName: 'Pantoprazole',
      drugClass: 'Proton Pump Inhibitor',
      aliases: ['Protonix', 'Pantop', 'Pantocid', 'Pan-D', 'Controloc'],
    ),
  };

  /// Cleans and normalizes query text.
  static String cleanQuery(String input) {
    return input
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\s#\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Normalizes user input into a canonical MedicineIdentity.
  static MedicineIdentity identify(String rawInput) {
    final cleaned = cleanQuery(rawInput);
    if (cleaned.isEmpty) {
      return MedicineIdentity(
        inputName: rawInput,
        genericName: 'UNKNOWN',
        displayName: 'Unknown Medicine',
      );
    }

    // Direct match against generic keys
    if (_knownDictionary.containsKey(cleaned)) {
      final entry = _knownDictionary[cleaned]!;
      return MedicineIdentity(
        inputName: rawInput,
        genericName: entry.genericName,
        displayName: entry.displayName,
        aliases: entry.aliases,
        activeIngredients: [entry.genericName == 'ASPIRIN' ? 'Aspirin' : entry.displayName],
        verified: true,
        confidence: 0.99,
        drugClass: entry.drugClass,
        foundLocally: true,
      );
    }

    // Match against aliases
    final matchedEntries = <_DrugEntry>[];
    for (final entry in _knownDictionary.values) {
      if (entry.matches(cleaned)) {
        matchedEntries.add(entry);
      }
    }

    if (matchedEntries.length == 1) {
      final entry = matchedEntries.first;
      return MedicineIdentity(
        inputName: rawInput,
        genericName: entry.genericName,
        displayName: entry.displayName,
        aliases: entry.aliases,
        activeIngredients: [entry.genericName == 'ASPIRIN' ? 'Aspirin' : entry.displayName],
        verified: true,
        confidence: 0.98,
        drugClass: entry.drugClass,
        foundLocally: true,
      );
    }

    if (matchedEntries.length > 1) {
      // Ambiguous query
      return MedicineIdentity(
        inputName: rawInput,
        genericName: matchedEntries.first.genericName,
        displayName: matchedEntries.first.displayName,
        isAmbiguous: true,
        ambiguousMatches: matchedEntries.map((e) => e.displayName).toList(),
      );
    }

    // Check fuzzy match on known dictionary
    final fuzzyMatches = _fuzzySearch(cleaned);
    if (fuzzyMatches.length == 1) {
      final entry = fuzzyMatches.first;
      return MedicineIdentity(
        inputName: rawInput,
        genericName: entry.genericName,
        displayName: entry.displayName,
        aliases: entry.aliases,
        activeIngredients: [entry.genericName == 'ASPIRIN' ? 'Aspirin' : entry.displayName],
        verified: true,
        confidence: 0.95,
        drugClass: entry.drugClass,
        foundLocally: true,
      );
    } else if (fuzzyMatches.length > 1) {
      return MedicineIdentity(
        inputName: rawInput,
        genericName: fuzzyMatches.first.genericName,
        displayName: fuzzyMatches.first.displayName,
        isAmbiguous: true,
        ambiguousMatches: fuzzyMatches.map((e) => e.displayName).toList(),
      );
    }

    final typoMatch = _closestEntry(cleaned);
    if (typoMatch != null) {
      return MedicineIdentity(
        inputName: rawInput,
        genericName: typoMatch.genericName,
        displayName: typoMatch.displayName,
        aliases: typoMatch.aliases,
        activeIngredients: [typoMatch.genericName == 'ASPIRIN' ? 'Aspirin' : typoMatch.displayName],
        drugClass: typoMatch.drugClass,
        foundLocally: true,
        verified: true,
        confidence: 0.94,
      );
    }

    // Not found in local dictionary - title case representation for online discovery.
    final titleCased = _toTitleCase(cleaned);
    return MedicineIdentity(
      inputName: rawInput,
      genericName: cleaned,
      displayName: titleCased,
      foundLocally: false,
      verified: false,
      confidence: 0.0,
    );
  }

  static List<_DrugEntry> _fuzzySearch(String term) {
    if (term.length < 3) return [];
    final results = <_DrugEntry>[];
    for (final entry in _knownDictionary.values) {
      if (entry.genericName.contains(term) ||
          entry.displayName.toUpperCase().contains(term) ||
          entry.aliases.any((a) => a.toUpperCase().contains(term))) {
        results.add(entry);
      }
    }
    return results;
  }

  static String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static _DrugEntry? _closestEntry(String term) {
    _DrugEntry? closest;
    var best = 3;
    for (final entry in _knownDictionary.values) {
      final candidates = [entry.genericName, entry.displayName, ...entry.aliases];
      for (final candidate in candidates) {
        final distance = _levenshtein(term, cleanQuery(candidate));
        if (distance < best) {
          best = distance;
          closest = entry;
        }
      }
    }
    return closest;
  }

  static int _levenshtein(String a, String b) {
    final previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      var diagonal = previous[0];
      previous[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final above = previous[j + 1];
        previous[j + 1] = a[i] == b[j]
            ? diagonal
            : 1 + [diagonal, previous[j], above].reduce((x, y) => x < y ? x : y);
        diagonal = above;
      }
    }
    return previous.last;
  }
}

class _DrugEntry {
  final String genericName;
  final String displayName;
  final String drugClass;
  final List<String> aliases;

  const _DrugEntry({
    required this.genericName,
    required this.displayName,
    required this.drugClass,
    required this.aliases,
  });

  bool matches(String query) {
    final normQuery = query.toUpperCase();
    if (genericName == normQuery) return true;
    if (displayName.toUpperCase() == normQuery) return true;
    for (final a in aliases) {
      if (a.toUpperCase() == normQuery) return true;
      if (a.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '') ==
          normQuery.replaceAll(RegExp(r'[^A-Z0-9]'), '')) {
        return true;
      }
    }
    return false;
  }
}
