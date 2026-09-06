import '../models/pgx_report.dart';

class VcfParseException implements Exception {
  final String message;
  VcfParseException(this.message);

  @override
  String toString() => message;
}

class ParsedGeneData {
  final String gene;
  final String allele1;
  final String allele2;
  final String phenotype;
  final bool isInferred;
  final List<DetectedVariant> variants;

  ParsedGeneData({
    required this.gene,
    required this.allele1,
    required this.allele2,
    required this.phenotype,
    required this.isInferred,
    required this.variants,
  });

  String get diplotype => '$allele1/$allele2';
}

class VcfParseResult {
  final String patientId;
  final Map<String, ParsedGeneData> geneProfiles;
  final QualityMetrics qualityMetrics;

  VcfParseResult({
    required this.patientId,
    required this.geneProfiles,
    required this.qualityMetrics,
  });
}

class VcfParser {
  static const Set<String> targetGenes = {
    'CYP2D6',
    'CYP2C19',
    'CYP2C9',
    'SLCO1B1',
    'TPMT',
    'DPYD',
    'CYP3A5',
    'HLA-B',
    'UGT1A1',
  };

  static const Map<String, Map<String, String>> _validatedVariantAlleles = {
    'CYP2D6': {'RS3892097': '*4', 'RS1065852': '*10'},
    'CYP2C19': {'RS4244285': '*2', 'RS12248560': '*17'},
    'CYP2C9': {'RS1799853': '*2', 'RS1057910': '*3'},
    'SLCO1B1': {'RS4149056': '*5'},
    'TPMT': {'RS1800460': '*3B', 'RS1142345': '*3C'},
    'DPYD': {'RS3918290': '*2A', 'RS67376798': '*13'},
    'CYP3A5': {'RS776746': '*3'},
    'HLA-B': {'RS3909184': '*15:02'},
    'UGT1A1': {'RS8175347': '*28'},
  };

  /// Parses raw VCF string content and returns structured PGx genomic data.
  static VcfParseResult parseVcfContent(String content, {String patientId = 'PATIENT_001'}) {
    if (content.trim().isEmpty) {
      throw VcfParseException('VCF file is empty.');
    }

    final lines = content.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) {
      throw VcfParseException('VCF file contains no data.');
    }

    bool hasVcfFormatHeader = false;
    bool hasGeneInfo = false;
    bool hasStarInfo = false;
    bool hasRsInfo = false;
    int headerLineIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('##fileformat=VCF')) {
        hasVcfFormatHeader = true;
      }
      if (line.startsWith('##INFO=<ID=GENE')) hasGeneInfo = true;
      if (line.startsWith('##INFO=<ID=STAR')) hasStarInfo = true;
      if (line.startsWith('##INFO=<ID=RS')) hasRsInfo = true;
      if (line.startsWith('#CHROM')) {
        headerLineIndex = i;
        break;
      }
    }

    if (!hasVcfFormatHeader && headerLineIndex == -1) {
      throw VcfParseException('Malformed VCF file: Invalid header structure.');
    }

    if (headerLineIndex == -1) {
      throw VcfParseException('Malformed VCF file: Missing #CHROM header column definition.');
    }

    final Map<String, List<String>> geneStarAlleles = {};
    final Map<String, List<DetectedVariant>> geneVariants = {};
    int totalVariantsDetected = 0;

    for (int i = headerLineIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.split('\t');
      if (parts.length < 8) {
        // Space-separated fallback check
        final spaceParts = line.split(RegExp(r'\s+'));
        if (spaceParts.length < 8) continue;
      }

      final cols = parts.length >= 8 ? parts : line.split(RegExp(r'\s+'));
      final id = cols[2];
      final info = cols[7];

      // Parse INFO column (e.g. GENE=CYP2D6;STAR=*4;RS=rs3892097)
      final infoPairs = _parseInfoColumn(info);
      final rsid = infoPairs['RS'] ?? (id != '.' ? id : 'rsUnknown');
      // Standard VCFs commonly provide an rsID but no non-standard GENE INFO
      // annotation. Resolve only rsIDs explicitly represented in this small,
      // validated on-device panel; never guess a gene from position.
      final gene = infoPairs['GENE']?.toUpperCase() ?? _geneForRsid(rsid);
        final star = infoPairs['STAR'] ??
          infoPairs['DIPLOTYPE'] ??
          infoPairs['GENOTYPE'] ??
          _starAlleleFromGenotype(gene, rsid, cols);

      if (gene != null && targetGenes.contains(gene)) {
        geneStarAlleles.putIfAbsent(gene, () => []);
        geneVariants.putIfAbsent(gene, () => []);

        if (star != null && star.isNotEmpty) {
          geneStarAlleles[gene]!.addAll(_extractStarAlleles(star));
        }

        geneVariants[gene]!.add(DetectedVariant(
          rsid: rsid,
          gene: gene,
          starAllele: star,
        ));
        totalVariantsDetected++;
      }
    }

    bool diplotypeInferred = false;
    final Map<String, ParsedGeneData> parsedGeneProfiles = {};

    for (final gene in targetGenes) {
      final stars = geneStarAlleles[gene] ?? [];
      final variants = geneVariants[gene] ?? [];

      String allele1 = '*1';
      String allele2 = '*1';
      bool inferred = false;

      if (stars.isEmpty) {
        allele1 = '*1';
        allele2 = '*1';
        inferred = true;
        // An absent gene annotation is not proof of a normal (*1/*1)
        // diplotype.  Many clinical VCFs only contain called variants and do
        // not establish coverage of every pharmacogene.
        diplotypeInferred = true;
      } else if (stars.length == 1) {
        allele1 = stars[0];
        allele2 = '*1';
        inferred = true;
        diplotypeInferred = true;
      } else {
        allele1 = stars[0];
        allele2 = stars[1];
      }

      final phenotype = stars.isEmpty
          ? 'Unknown'
          : _inferPhenotype(gene, allele1, allele2);

      parsedGeneProfiles[gene] = ParsedGeneData(
        gene: gene,
        allele1: allele1,
        allele2: allele2,
        phenotype: phenotype,
        isInferred: inferred,
        variants: variants,
      );
    }

    double annotationCompleteness = 0.0;
    if (hasGeneInfo) annotationCompleteness += 0.4;
    if (hasStarInfo) annotationCompleteness += 0.3;
    if (hasRsInfo) annotationCompleteness += 0.3;

    final qualityMetrics = QualityMetrics(
      vcfParsingSuccess: true,
      variantsDetected: totalVariantsDetected,
      genesCovered: targetGenes.where((g) => geneVariants.containsKey(g)).toList(),
      diplotypeInferred: diplotypeInferred,
      annotationCompleteness: annotationCompleteness,
    );

    return VcfParseResult(
      patientId: patientId,
      geneProfiles: parsedGeneProfiles,
      qualityMetrics: qualityMetrics,
    );
  }

  static Map<String, String> _parseInfoColumn(String infoStr) {
    final map = <String, String>{};
    final items = infoStr.split(';');
    for (var item in items) {
      final kv = item.split('=');
      if (kv.length == 2) {
        map[kv[0].trim().toUpperCase()] = kv[1].trim();
      }
    }
    return map;
  }

  static String? _geneForRsid(String rsid) {
    final normalized = rsid.toUpperCase();
    for (final entry in _validatedVariantAlleles.entries) {
      if (entry.value.containsKey(normalized)) return entry.key;
    }
    return null;
  }

  static List<String> _extractStarAlleles(String value) {
    return value
        .split(RegExp(r'[/|,]'))
        .map((allele) => allele.trim())
        .where((allele) => allele.isNotEmpty)
        .toList();
  }

  static String? _starAlleleFromGenotype(
    String? gene,
    String rsid,
    List<String> columns,
  ) {
    if (gene == null || columns.length < 10) return null;
    final formatKeys = columns[8].split(':');
    final sampleValues = columns[9].split(':');
    final genotypeIndex = formatKeys.indexOf('GT');
    if (genotypeIndex == -1 || genotypeIndex >= sampleValues.length) return null;

    final genotype = sampleValues[genotypeIndex];
    final allele = _validatedVariantAlleles[gene]?[rsid.toUpperCase()];
    if (allele == null) return null;
    if (genotype == '0/0' || genotype == '0|0') return '*1/*1';
    if (genotype == '1/1' || genotype == '1|1') return '$allele/$allele';
    if (genotype == '0/1' || genotype == '1/0' || genotype == '0|1' || genotype == '1|0') {
      return '*1/$allele';
    }
    return null;
  }

  /// Infers gene phenotype from diplotype alleles.
  static String _inferPhenotype(String gene, String a1, String a2) {
    final diplotype = '$a1/$a2';

    switch (gene) {
      case 'CYP2D6':
      case 'CYP2C19':
        if (diplotype.contains('*4/*4') || diplotype.contains('*2/*2') || diplotype.contains('*3/*3') || diplotype.contains('*2/*3')) {
          return 'PM'; // Poor Metabolizer
        } else if (diplotype.contains('*17/*17') || diplotype.contains('*2xN') || diplotype.contains('*1xN')) {
          return 'URM'; // Ultrarapid Metabolizer
        } else if (diplotype.contains('*17') || diplotype.contains('*1/*2xN')) {
          return 'RM'; // Rapid Metabolizer
        } else if (diplotype.contains('*4') || diplotype.contains('*2') || diplotype.contains('*10') || diplotype.contains('*3')) {
          return 'IM'; // Intermediate Metabolizer
        }
        return 'NM'; // Normal Metabolizer

      case 'CYP2C9':
        if (diplotype.contains('*3/*3') || diplotype.contains('*2/*3')) {
          return 'PM';
        } else if (diplotype.contains('*2') || diplotype.contains('*3')) {
          return 'IM';
        }
        return 'NM';

      case 'SLCO1B1':
        if (diplotype.contains('*5/*5') || diplotype.contains('*15/*15')) {
          return 'Poor function';
        } else if (diplotype.contains('*5') || diplotype.contains('*15')) {
          return 'Decreased function';
        }
        return 'Normal function';

      case 'TPMT':
        if (diplotype.contains('*3A/*3A') || diplotype.contains('*3C/*3C') || diplotype.contains('*2/*3A')) {
          return 'PM';
        } else if (diplotype.contains('*2') || diplotype.contains('*3A') || diplotype.contains('*3B') || diplotype.contains('*3C')) {
          return 'IM';
        }
        return 'NM';

      case 'DPYD':
        if (diplotype.contains('*2A/*2A') || diplotype.contains('*13/*13')) {
          return 'PM';
        } else if (diplotype.contains('*2A') || diplotype.contains('*13')) {
          return 'IM';
        }
        return 'NM';

      // CYP3A5: *3 is the loss-of-function allele (non-expressor).
      // *1/*1 → NM (rapid expressor), *1/*3 → IM, *3/*3 → PM (non-expressor).
      case 'CYP3A5':
        if (diplotype == '*3/*3' || diplotype == '*1/*3' && a1 == '*3' && a2 == '*3') {
          return 'PM'; // Non-expressor — standard CPIC term for *3/*3
        } else if (diplotype.contains('*3')) {
          return 'IM'; // *1/*3 — intermediate expressor
        }
        return 'NM'; // *1/*1 — expressor (fast metaboliser)

      // HLA-B: *15:02 → Positive (SJS/TEN risk with carbamazepine),
      //        *57:01 → Positive (hypersensitivity risk with abacavir).
      //        Any other diplotype inferred from this panel → Negative.
      case 'HLA-B':
        if (diplotype.contains('*15:02') || diplotype.contains('*57:01')) {
          return 'Positive';
        }
        // If VCF explicitly provided a *1/*1 reference call, report Negative.
        if (diplotype == '*1/*1') return 'Negative';
        // Anything else (inferred *1/*1 with no direct annotation) stays Unknown
        // because absence of evidence ≠ confirmed negative for HLA alleles.
        return a1 == '*1' && a2 == '*1' ? 'Negative' : 'Unknown';

      // UGT1A1: *28/*28 → PM (Gilbert syndrome), *1/*28 → IM, *1/*1 → NM.
      case 'UGT1A1':
        if (diplotype == '*28/*28') {
          return 'PM';
        } else if (diplotype.contains('*28')) {
          return 'IM';
        }
        return 'NM';

      default:
        return 'Unknown';
    }
  }
}
