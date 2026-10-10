import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_profile.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../services/patient_profile_service.dart';

class PatientProfileScreen extends ConsumerStatefulWidget {
  final bool isInitialSetup;

  const PatientProfileScreen({super.key, this.isInitialSetup = false});

  @override
  ConsumerState<PatientProfileScreen> createState() =>
      _PatientProfileScreenState();
}

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _patientIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _allergyController = TextEditingController();
  final _medicineController = TextEditingController();
  final _conditionController = TextEditingController();

  String _selectedSex = 'Other / Prefer not to say';
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
      _nameController.text = profile.fullName.isNotEmpty
          ? profile.fullName
          : FirebaseService.currentUser?.displayName ?? '';
      _patientIdController.text = profile.patientId;
      _emailController.text = profile.email.isNotEmpty
          ? profile.email
          : FirebaseService.currentUser?.email ?? '';
      _phoneController.text = profile.phoneNumber;
      _dateOfBirthController.text = profile.dateOfBirth;
      _ageController.text = profile.age;
      _weightController.text = profile.weight;
      _heightController.text = profile.height;
      _allergies.clear();
      _currentMedicines.clear();
      _conditions.clear();
      if (profile.sex.isNotEmpty) _selectedSex = profile.sex;
      if (profile.allergies.isNotEmpty) {
        _allergyStatus = 'Yes';
        _allergies.addAll(profile.allergies);
      } else {
        _allergyStatus = 'No';
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
    _nameController.dispose();
    _patientIdController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dateOfBirthController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
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

  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dateOfBirthController.text =
          '${selected.day.toString().padLeft(2, '0')}/'
          '${selected.month.toString().padLeft(2, '0')}/${selected.year}';
      _ageController.text = _ageFromDate(selected, now).toString();
    });
  }

  int _ageFromDate(DateTime dateOfBirth, DateTime today) {
    var age = today.year - dateOfBirth.year;
    if (today.month < dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = PatientProfile(
      fullName: _nameController.text.trim(),
      patientId: _patientIdController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      dateOfBirth: _dateOfBirthController.text.trim(),
      age: _ageController.text.trim(),
      sex: _selectedSex,
      weight: _weightController.text.trim(),
      height: _heightController.text.trim(),
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
      Navigator.of(context).pop();
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: !widget.isInitialSetup,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isInitialSetup
                ? 'Complete your patient profile'
                : 'Edit patient profile',
          ),
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
                        theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.6,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.health_and_safety_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black87,
                        ),
                      ),
                      if (vcfFilename != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.biotech,
                              size: 16,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Genetic VCF: $vcfFilename',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 1. Identity and contact details
                _buildSectionCard(
                  title: 'Patient details',
                  icon: Icons.badge_outlined,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter the patient name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _patientIdController,
                        decoration: const InputDecoration(
                          labelText: 'Patient ID *',
                          hintText: 'Your clinic or personal record ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a patient ID'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(
                                  r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$',
                                ).hasMatch(value.trim())
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone number *',
                          hintText: 'Include country code when applicable',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 7
                            ? 'Enter a valid phone number'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dateOfBirthController,
                        readOnly: true,
                        onTap: _selectDateOfBirth,
                        decoration: const InputDecoration(
                          labelText: 'Date of birth *',
                          hintText: 'DD/MM/YYYY',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.cake_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Select a date of birth'
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Demographics and measurements
                _buildSectionCard(
                  title: 'Demographics and measurements',
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _heightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Height (cm, optional)',
                          hintText: 'e.g. 165',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.height),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Gender / sex relevant to care:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children:
                            ['Male', 'Female', 'Other / Prefer not to say'].map(
                              (sex) {
                                final isSelected = _selectedSex == sex;
                                return ChoiceChip(
                                  label: Text(sex),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() => _selectedSex = sex);
                                    }
                                  },
                                );
                              },
                            ).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Known Allergies Card
                _buildSectionCard(
                  title: 'Known Medicine Allergies',
                  icon: Icons.warning_amber_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Do you have known medicine allergies?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
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
                                if (val) {
                                  setState(() => _allergyStatus = status);
                                }
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
                                  hintText:
                                      'Enter allergy (e.g. Aspirin, Penicillin)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: _addAllergy,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: () =>
                                  _addAllergy(_allergyController.text),
                              icon: const Icon(Icons.add),
                              tooltip: 'Add allergy',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Quick Select:',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _commonAllergies.map((all) {
                            final alreadyAdded = _allergies.contains(all);
                            return FilterChip(
                              label: Text(
                                all,
                                style: const TextStyle(fontSize: 12),
                              ),
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
                          const Text(
                            'Your Reported Allergies:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: _allergies.map((all) {
                              return Chip(
                                backgroundColor: Colors.red.shade50,
                                side: BorderSide(color: Colors.red.shade200),
                                label: Text(
                                  all,
                                  style: TextStyle(
                                    color: Colors.red.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () =>
                                    setState(() => _allergies.remove(all)),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Current Medicines Card
                _buildSectionCard(
                  title: 'Current Medicines',
                  icon: Icons.medication_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'List all prescriptions, OTC drugs, or anticoagulants you currently take:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _medicineController,
                              decoration: const InputDecoration(
                                hintText:
                                    'e.g. Warfarin, Clopidogrel, Omeprazole',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: _addMedicine,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () =>
                                _addMedicine(_medicineController.text),
                            icon: const Icon(Icons.add),
                            tooltip: 'Add medicine',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Quick Select Common Interacting Drugs:',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _commonMedicines.map((med) {
                          final alreadyAdded = _currentMedicines.contains(med);
                          return FilterChip(
                            label: Text(
                              med,
                              style: const TextStyle(fontSize: 12),
                            ),
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
                        const Text(
                          'Your Active Regimen:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: _currentMedicines.map((med) {
                            return Chip(
                              backgroundColor: Colors.blue.shade50,
                              side: BorderSide(color: Colors.blue.shade200),
                              label: Text(
                                med,
                                style: TextStyle(color: Colors.blue.shade900),
                              ),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () =>
                                  setState(() => _currentMedicines.remove(med)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Medical Conditions Card
                _buildSectionCard(
                  title: 'Medical Conditions & History',
                  icon: Icons.healing_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Past or present conditions (especially ulcers, bleeding, asthma):',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _conditionController,
                              decoration: const InputDecoration(
                                hintText:
                                    'e.g. Peptic ulcer, Asthma, Hypertension',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: _addCondition,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () =>
                                _addCondition(_conditionController.text),
                            icon: const Icon(Icons.add),
                            tooltip: 'Add condition',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Quick Select:',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _commonConditions.map((cond) {
                          final alreadyAdded = _conditions.contains(cond);
                          return FilterChip(
                            label: Text(
                              cond,
                              style: const TextStyle(fontSize: 12),
                            ),
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
                        const Text(
                          'Reported Conditions:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: _conditions.map((cond) {
                            return Chip(
                              backgroundColor: Colors.amber.shade50,
                              side: BorderSide(color: Colors.amber.shade300),
                              label: Text(
                                cond,
                                style: TextStyle(color: Colors.amber.shade900),
                              ),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () =>
                                  setState(() => _conditions.remove(cond)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Organ Function (Kidney & Liver)
                _buildSectionCard(
                  title: 'Organ Function & Health',
                  icon: Icons.monitor_heart_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kidney Disease / Function:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _kidneyFunction,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Normal function / No known disease',
                            child: Text('Normal / No known disease'),
                          ),
                          DropdownMenuItem(
                            value: 'Mild renal impairment',
                            child: Text('Mild impairment'),
                          ),
                          DropdownMenuItem(
                            value: 'Moderate renal impairment',
                            child: Text('Moderate impairment'),
                          ),
                          DropdownMenuItem(
                            value: 'Severe renal disease / Dialysis',
                            child: Text('Severe disease / Dialysis'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _kidneyFunction = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Liver Disease / Function:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _liverFunction,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Normal function / No known disease',
                            child: Text('Normal / No known disease'),
                          ),
                          DropdownMenuItem(
                            value: 'Mild hepatic impairment',
                            child: Text('Mild impairment'),
                          ),
                          DropdownMenuItem(
                            value:
                                'Moderate to severe liver disease / Cirrhosis',
                            child: Text(
                              'Moderate to severe disease / Cirrhosis',
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _liverFunction = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 7. Pregnancy / Breastfeeding (Contextual, shown prominently if female)
                if (_selectedSex == 'Female') ...[
                  _buildSectionCard(
                    title: 'Pregnancy & Breastfeeding',
                    icon: Icons.pregnant_woman_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _pregnancyStatus,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Not pregnant / Not applicable',
                              child: Text('Not pregnant / Not applicable'),
                            ),
                            DropdownMenuItem(
                              value:
                                  'Currently pregnant (1st or 2nd trimester)',
                              child: Text('Pregnant (1st or 2nd trimester)'),
                            ),
                            DropdownMenuItem(
                              value: 'Currently pregnant (3rd trimester)',
                              child: Text('Pregnant (3rd trimester)'),
                            ),
                            DropdownMenuItem(
                              value: 'Currently breastfeeding',
                              child: Text('Currently breastfeeding'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _pregnancyStatus = val);
                            }
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    widget.isInitialSetup
                        ? 'Save profile and open dashboard'
                        : 'Save patient profile',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
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
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
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
