import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_profile.dart';
import '../providers/app_providers.dart';
import '../services/patient_profile_service.dart';
import 'drug_input_screen.dart';

class PatientProfileScreen extends ConsumerStatefulWidget {
  final bool isInitialSetup;

  const PatientProfileScreen({super.key, this.isInitialSetup = false});

  @override
  ConsumerState<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _allergyController = TextEditingController();
  final _medicineController = TextEditingController();
  final _conditionController = TextEditingController();

  String _selectedSex = 'Prefer not to say';
  String _allergyStatus = 'No'; // 'Yes', 'No', 'Not sure'
  final List<String> _allergies = [];
  final List<String> _currentMedicines = [];
  final List<String> _conditions = [];
  String _pregnancyStatus = 'Not pregnant / Not applicable';
  String _kidneyFunction = 'Normal function / No known disease';
  String _liverFunction = 'Normal function / No known disease';

  bool _isLoading = true;

  static const _commonAllergies = [
    'Penicillin',
    'Aspirin / NSAIDs',
    'Sulfa drugs',
    'Opioids',
    'Amoxicillin',
  ];

  static const _commonMedicines = [
    'Warfarin',
    'Apixaban',
    'Clopidogrel',
    'Aspirin',
    'Simvastatin',
    'Atorvastatin',
    'Omeprazole',
    'Lisinopril',
    'Metformin',
    'Amlodipine',
  ];

  static const _commonConditions = [
    'Peptic ulcer / Gastritis',
    'Gastrointestinal bleeding',
    'Asthma',
    'Hypertension',
    'Type 2 Diabetes',
    'Chronic Kidney Disease',
    'Liver disease / Cirrhosis',
    'Coronary Artery Disease',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final profile = await PatientProfileService.load();
    if (!mounted) return;

    setState(() {
      _ageController.text = profile.age;
      _weightController.text = profile.weight;
      if (profile.sex.isNotEmpty) _selectedSex = profile.sex;
      if (profile.allergies.isNotEmpty) {
        _allergyStatus = 'Yes';
        _allergies.addAll(profile.allergies);
      }
      _currentMedicines.addAll(profile.currentMedicines);
      _conditions.addAll(profile.conditions);
      if (profile.pregnancyStatus.isNotEmpty) {
        _pregnancyStatus = profile.pregnancyStatus;
      }
      if (profile.kidneyFunction.isNotEmpty) {
        _kidneyFunction = profile.kidneyFunction;
      }
      if (profile.liverFunction.isNotEmpty) {
        _liverFunction = profile.liverFunction;
      }
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _allergyController.dispose();
    _medicineController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  void _addAllergy(String allergy) {
    final trimmed = allergy.trim();
    if (trimmed.isNotEmpty && !_allergies.contains(trimmed)) {
      setState(() {
        _allergies.add(trimmed);
        _allergyStatus = 'Yes';
        _allergyController.clear();
      });
    }
  }

  void _addMedicine(String med) {
    final trimmed = med.trim();
    if (trimmed.isNotEmpty && !_currentMedicines.contains(trimmed)) {
      setState(() {
        _currentMedicines.add(trimmed);
        _medicineController.clear();
      });
    }
  }

  void _addCondition(String cond) {
    final trimmed = cond.trim();
    if (trimmed.isNotEmpty && !_conditions.contains(trimmed)) {
      setState(() {
        _conditions.add(trimmed);
        _conditionController.clear();
      });
    }
  }

  Future<void> _saveProfile() async {
    final profile = PatientProfile(
      patientId: ref.read(vcfParseResultProvider)?.patientId ?? 'PATIENT_001',
      age: _ageController.text.trim(),
      sex: _selectedSex,
      weight: _weightController.text.trim(),
      allergies: _allergyStatus == 'Yes' ? _allergies : const [],
      currentMedicines: _currentMedicines,
      conditions: _conditions,
      pregnancyStatus: _selectedSex == 'Female' ? _pregnancyStatus : '',
      kidneyFunction: _kidneyFunction,
      liverFunction: _liverFunction,
      vcfFilename: ref.read(selectedVcfFilenameProvider),
    );

    await PatientProfileService.save(profile);
    ref.read(patientProfileProvider.notifier).state = profile;

    if (!mounted) return;

    if (widget.isInitialSetup) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DrugInputScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Health Profile saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vcfFilename = ref.watch(selectedVcfFilenameProvider);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isInitialSetup ? 'Patient Clinical Profile' : 'Edit Health Profile'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Header description banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.health_and_safety_rounded, color: theme.colorScheme.primary, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'YOUR HEALTH PROFILE',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'PharmaGuard uses this clinical data alongside your local genetic file to calculate drug interactions, allergy alerts, and personalized side-effect risks.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87),
                    ),
                    if (vcfFilename != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.biotech, size: 16, color: Colors.teal),
                          const SizedBox(width: 6),
                          Text('Genetic VCF: $vcfFilename', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 1. Demographics Card (Age, Sex, Weight)
              _buildSectionCard(
                title: 'Demographics',
                icon: Icons.person_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Age (years)',
                              hintText: 'e.g. 62',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.cake_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Weight (kg)',
                              hintText: 'e.g. 70',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.monitor_weight_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Biological Sex:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Male', 'Female', 'Other / Prefer not to say'].map((sex) {
                        final isSelected = _selectedSex == sex;
                        return ChoiceChip(
                          label: Text(sex),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedSex = sex);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Known Allergies Card
              _buildSectionCard(
                title: 'Known Medicine Allergies',
                icon: Icons.warning_amber_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Do you have known medicine allergies?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: ['No', 'Yes', 'Not sure'].map((status) {
                        final isSelected = _allergyStatus == status;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(status),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) setState(() => _allergyStatus = status);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                    if (_allergyStatus == 'Yes') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _allergyController,
                              decoration: const InputDecoration(
                                hintText: 'Enter allergy (e.g. Aspirin, Penicillin)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: _addAllergy,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () => _addAllergy(_allergyController.text),
                            icon: const Icon(Icons.add),
                            tooltip: 'Add allergy',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('Quick Select:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _commonAllergies.map((all) {
                          final alreadyAdded = _allergies.contains(all);
                          return FilterChip(
                            label: Text(all, style: const TextStyle(fontSize: 12)),
                            selected: alreadyAdded,
                            onSelected: (selected) {
                              if (selected) {
                                _addAllergy(all);
                              } else {
                                setState(() => _allergies.remove(all));
                              }
                            },
                          );
                        }).toList(),
                      ),
                      if (_allergies.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Your Reported Allergies:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: _allergies.map((all) {
                            return Chip(
                              backgroundColor: Colors.red.shade50,
                              side: BorderSide(color: Colors.red.shade200),
                              label: Text(all, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => setState(() => _allergies.remove(all)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Current Medicines Card
              _buildSectionCard(
                title: 'Current Medicines',
                icon: Icons.medication_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('List all prescriptions, OTC drugs, or anticoagulants you currently take:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _medicineController,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Warfarin, Clopidogrel, Omeprazole',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: _addMedicine,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () => _addMedicine(_medicineController.text),
                          icon: const Icon(Icons.add),
                          tooltip: 'Add medicine',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Quick Select Common Interacting Drugs:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _commonMedicines.map((med) {
                        final alreadyAdded = _currentMedicines.contains(med);
                        return FilterChip(
                          label: Text(med, style: const TextStyle(fontSize: 12)),
                          selected: alreadyAdded,
                          onSelected: (selected) {
                            if (selected) {
                              _addMedicine(med);
                            } else {
                              setState(() => _currentMedicines.remove(med));
                            }
                          },
                        );
                      }).toList(),
                    ),
                    if (_currentMedicines.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Your Active Regimen:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: _currentMedicines.map((med) {
                          return Chip(
                            backgroundColor: Colors.blue.shade50,
                            side: BorderSide(color: Colors.blue.shade200),
                            label: Text(med, style: TextStyle(color: Colors.blue.shade900)),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(() => _currentMedicines.remove(med)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. Medical Conditions Card
              _buildSectionCard(
                title: 'Medical Conditions & History',
                icon: Icons.healing_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Past or present conditions (especially ulcers, bleeding, asthma):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _conditionController,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Peptic ulcer, Asthma, Hypertension',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: _addCondition,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () => _addCondition(_conditionController.text),
                          icon: const Icon(Icons.add),
                          tooltip: 'Add condition',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Quick Select:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _commonConditions.map((cond) {
                        final alreadyAdded = _conditions.contains(cond);
                        return FilterChip(
                          label: Text(cond, style: const TextStyle(fontSize: 12)),
                          selected: alreadyAdded,
                          onSelected: (selected) {
                            if (selected) {
                              _addCondition(cond);
                            } else {
                              setState(() => _conditions.remove(cond));
                            }
                          },
                        );
                      }).toList(),
                    ),
                    if (_conditions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Reported Conditions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: _conditions.map((cond) {
                          return Chip(
                            backgroundColor: Colors.amber.shade50,
                            side: BorderSide(color: Colors.amber.shade300),
                            label: Text(cond, style: TextStyle(color: Colors.amber.shade900)),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(() => _conditions.remove(cond)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 5. Organ Function (Kidney & Liver)
              _buildSectionCard(
                title: 'Organ Function & Health',
                icon: Icons.monitor_heart_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kidney Disease / Function:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _kidneyFunction,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'Normal function / No known disease', child: Text('Normal / No known disease')),
                        DropdownMenuItem(value: 'Mild renal impairment', child: Text('Mild impairment')),
                        DropdownMenuItem(value: 'Moderate renal impairment', child: Text('Moderate impairment')),
                        DropdownMenuItem(value: 'Severe renal disease / Dialysis', child: Text('Severe disease / Dialysis')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _kidneyFunction = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Liver Disease / Function:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _liverFunction,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'Normal function / No known disease', child: Text('Normal / No known disease')),
                        DropdownMenuItem(value: 'Mild hepatic impairment', child: Text('Mild impairment')),
                        DropdownMenuItem(value: 'Moderate to severe liver disease / Cirrhosis', child: Text('Moderate to severe disease / Cirrhosis')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _liverFunction = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 6. Pregnancy / Breastfeeding (Contextual, shown prominently if female)
              if (_selectedSex == 'Female') ...[
                _buildSectionCard(
                  title: 'Pregnancy & Breastfeeding',
                  icon: Icons.pregnant_woman_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _pregnancyStatus,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'Not pregnant / Not applicable', child: Text('Not pregnant / Not applicable')),
                          DropdownMenuItem(value: 'Currently pregnant (1st or 2nd trimester)', child: Text('Pregnant (1st or 2nd trimester)')),
                          DropdownMenuItem(value: 'Currently pregnant (3rd trimester)', child: Text('Pregnant (3rd trimester)')),
                          DropdownMenuItem(value: 'Currently breastfeeding', child: Text('Currently breastfeeding')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _pregnancyStatus = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 12),

              // Action button
              FilledButton.icon(
                onPressed: _saveProfile,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  widget.isInitialSetup ? 'Save Profile & Continue to Medications' : 'Save Health Profile',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
