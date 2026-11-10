import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_inputs.dart';

/// Lets a customer record household details (size, average daily
/// consumption, how often they usually order, and their usual order
/// size) so the forecast/reminder features have something concrete to
/// work from per-customer, not just the aggregate daily totals.
///
/// One row per customer in `customer_household_info` - saving again
/// overwrites the existing row (upsert) rather than creating duplicates.
class HouseholdInfoScreen extends StatefulWidget {
  const HouseholdInfoScreen({super.key});

  @override
  State<HouseholdInfoScreen> createState() => _HouseholdInfoScreenState();
}

class _HouseholdInfoScreenState extends State<HouseholdInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _peopleController = TextEditingController();
  final _consumptionController = TextEditingController();
  final _gallonsController = TextEditingController();
  int _frequencyDays = 7;

  bool _isLoading = true;
  bool _isSaving = false;

  static const _frequencyOptions = [3, 5, 7, 10, 14];

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _peopleController.dispose();
    _consumptionController.dispose();
    _gallonsController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final existing = await Supabase.instance.client
          .from('customer_household_info')
          .select()
          .eq('customer_id', customerId)
          .maybeSingle();

      if (existing != null && mounted) {
        _peopleController.text = existing['household_size'].toString();
        _consumptionController.text = existing['avg_daily_consumption_liters'].toString();
        _gallonsController.text = existing['usual_gallons_per_order'].toString();
        setState(() => _frequencyDays = existing['order_frequency_days'] as int);
      }
    } catch (_) {
      // No existing row yet is expected for a first-time save.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveInfo() async {
    if (!_formKey.currentState!.validate()) return;

    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) return;

    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client.from('customer_household_info').upsert({
        'customer_id': customerId,
        'household_size': int.parse(_peopleController.text.trim()),
        'avg_daily_consumption_liters': double.parse(_consumptionController.text.trim()),
        'order_frequency_days': _frequencyDays,
        'usual_gallons_per_order': int.parse(_gallonsController.text.trim()),
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Information saved successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving information: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Household Information')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Please provide your household details',
                      style: TextStyle(fontSize: 15, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 22),
                    _buildField(
                      label: 'Number of People in House',
                      controller: _peopleController,
                      hint: '5',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 18),
                    _buildField(
                      label: 'Average Daily Water Consumption',
                      controller: _consumptionController,
                      hint: '20',
                      suffixText: 'Liters',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 18),
                    const FieldLabel('How often do you order water?'),
                    DropdownButtonFormField<int>(
                      value: _frequencyDays,
                      decoration: outlinedField(),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      items: _frequencyOptions
                          .map((d) => DropdownMenuItem(value: d, child: Text('Every $d days')))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _frequencyDays = val);
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildField(
                      label: 'Gallons per Order (usually)',
                      controller: _gallonsController,
                      hint: '5',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveInfo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'SAVE INFORMATION',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? suffixText,
    TextInputType? keyboardType,
    bool isDecimal = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType ?? (isDecimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number),
          inputFormatters: [isDecimal ? InputFormatters.decimal : InputFormatters.numbersOnly],
          decoration: outlinedField(hint: hint, suffixText: suffixText),
          validator: (v) {
            if (isDecimal) {
              return InputValidators.decimalNumber(v, fieldName: label, min: 0.1);
            }
            return InputValidators.numbersOnly(v, fieldName: label);
          },
        ),
      ],
    );
  }
}
