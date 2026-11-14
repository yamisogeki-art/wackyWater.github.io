import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/pricing.dart';
import '../../services/driver_delivery_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';

class TransactionRecordScreen extends StatefulWidget {
  final DeliveryStop? stop;
  final DriverStopsController? controller;
  final String? customerName;
  final String? location;
  final double? initialGallons;
  final String? initialWaterType;
  final bool showFormInitially;

  const TransactionRecordScreen({
    super.key,
    this.stop,
    this.controller,
    this.customerName,
    this.location,
    this.initialGallons,
    this.initialWaterType,
    this.showFormInitially = false,
  });

  @override
  State<TransactionRecordScreen> createState() => _TransactionRecordScreenState();
}

class _TransactionRecordScreenState extends State<TransactionRecordScreen> with SingleTickerProviderStateMixin {
  late final Stream<List<Map<String, dynamic>>> _transactionsStream;
  late TabController _tabController;

  // Form Controllers
  late final TextEditingController _userNameController;
  late final TextEditingController _locationController;

  int _quantity = 2;
  String _waterType = 'purified'; // only purified water is sold
  String _orderType = 'refill'; // 'refill' | 'exchange'
  String _status = 'Delivered - Paid';
  String _paymentType = 'Cash on Delivery';
  bool _isSubmitting = false;

  // Selected customer for manual entry
  String? _selectedCustomerId;
  List<Map<String, dynamic>> _customerProfiles = [];

  // Real-time lookup caches for related customer profiles, addresses, and delivery requests
  final Map<String, String> _profileNames = {};
  final Map<dynamic, Map<String, dynamic>> _addressMap = {};
  final Map<dynamic, Map<String, dynamic>> _orderMap = {};

  // Proof of Delivery photo state
  XFile? _proofPhoto;
  final ImagePicker _picker = ImagePicker();

  Future<void> _takeProofPhoto(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (photo != null && mounted) {
        setState(() => _proofPhoto = photo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $e')),
        );
      }
    }
  }

  Future<void> _loadCustomerProfiles() async {
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email')
          .order('full_name');
      if (mounted) {
        setState(() {
          _customerProfiles = List<Map<String, dynamic>>.from(rows);
          if (widget.stop != null) {
            _selectedCustomerId = widget.stop!.request['customer_id']?.toString();
          } else if (_customerProfiles.isNotEmpty) {
            _selectedCustomerId = _customerProfiles.first['id']?.toString();
            final firstCust = _customerProfiles.first;
            if (_userNameController.text.isEmpty) {
              _userNameController.text = (firstCust['full_name'] as String?) ?? 'Customer';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Could not load customer profiles: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    final name = widget.customerName ?? widget.stop?.name ?? '';
    final loc = widget.location ?? widget.stop?.addressLine ?? '';
    _userNameController = TextEditingController(text: name);
    _locationController = TextEditingController(text: loc);

    if (widget.initialGallons != null && widget.initialGallons! > 0) {
      _quantity = widget.initialGallons!.toInt();
    } else if (widget.stop != null) {
      _quantity = widget.stop!.gallons;
    }

    if (widget.initialWaterType != null) {
      _waterType = widget.initialWaterType!;
    } else if (widget.stop != null) {
      _waterType = widget.stop!.waterType;
    }

    if (widget.stop != null) {
      _orderType = widget.stop!.orderType;
    }

    final initialIndex = (widget.showFormInitially || widget.stop != null) ? 1 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex);

    _loadCustomerProfiles();

    // Real-time Database Subscription
    _transactionsStream = Supabase.instance.client
        .from('customer_transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  double get _pricePerGallon => pricePerGallonFor(_waterType);
  double get _totalPrice => _quantity * _pricePerGallon;

  /// Loads missing customer names and locations if not directly present in customer_transactions
  Future<void> _ensureMetadataLoaded(List<Map<String, dynamic>> rawTxList) async {
    final client = Supabase.instance.client;

    final missingCustomerIds = rawTxList
        .map((tx) => tx['customer_id']?.toString())
        .whereType<String>()
        .where((id) => !_profileNames.containsKey(id))
        .toSet()
        .toList();

    if (missingCustomerIds.isNotEmpty) {
      try {
        final profiles = await client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', missingCustomerIds);
        if (mounted) {
          setState(() {
            for (final p in List<Map<String, dynamic>>.from(profiles)) {
              final id = p['id'].toString();
              final name = p['full_name'] as String?;
              if (name != null && name.trim().isNotEmpty) {
                _profileNames[id] = name.trim();
              }
            }
          });
        }
      } catch (e) {
        debugPrint('Could not load profile names: $e');
      }
    }

    final missingOrderIds = rawTxList
        .map((tx) => tx['delivery_request_id'])
        .where((id) => id != null && !_orderMap.containsKey(id))
        .toSet()
        .toList();

    if (missingOrderIds.isNotEmpty) {
      try {
        final orders = await client
            .from('delivery_requests')
            .select('id, address_id, water_type, order_type')
            .inFilter('id', missingOrderIds);
        if (mounted) {
          setState(() {
            for (final o in List<Map<String, dynamic>>.from(orders)) {
              _orderMap[o['id']] = o;
            }
          });
        }

        final addressIds = orders
            .map((o) => o['address_id'])
            .where((id) => id != null && !_addressMap.containsKey(id))
            .toSet()
            .toList();

        if (addressIds.isNotEmpty) {
          final addresses = await client
              .from('customer_addresses')
              .select('id, label, area')
              .inFilter('id', addressIds);
          if (mounted) {
            setState(() {
              for (final a in List<Map<String, dynamic>>.from(addresses)) {
                _addressMap[a['id']] = a;
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Could not load delivery request metadata: $e');
      }
    }
  }

  Future<void> _submitRecord() async {
    final customerId = widget.stop?.request['customer_id']?.toString() ?? _selectedCustomerId;
    if (customerId == null || customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid customer.')),
      );
      return;
    }

    final locationText = _locationController.text.trim();
    if (locationText.isNotEmpty) {
      final locError = InputValidators.alphanumeric(locationText, fieldName: 'Delivery Location');
      if (locError != null) {
        InputErrorHandler.showErrorSnackBar(context, locError);
        return;
      }
    }

    setState(() => _isSubmitting = true);
    final client = Supabase.instance.client;
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final isPaid = _status.contains('Paid');

    try {
      if (widget.stop != null && widget.controller != null) {
        final result = await widget.controller!.completeDelivery(
          stop: widget.stop!,
          gallons: _quantity.toDouble(),
          pricePerGallon: _pricePerGallon,
          waterType: _waterType,
          orderType: _orderType,
          paidInFull: isPaid,
        );

        if (!result.ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${result.error}')),
          );
          return;
        }
      } else {
        // Direct database insert into customer_transactions (using valid DB schema columns)
        await client.from('customer_transactions').insert({
          'customer_id': customerId,
          'transaction_date': dateStr,
          'gallons': _quantity.toDouble(),
          'price_per_gallon': _pricePerGallon,
          'water_type': _waterType,
          'amount_paid': isPaid ? _totalPrice : 0,
          'status': isPaid ? 'paid' : 'unpaid',
        });

        // Sync aggregate total for demand forecasting
        try {
          await client.rpc('upsert_daily_gallons', params: {
            'p_date': dateStr,
            'p_gallons': _quantity.toDouble(),
          });
        } catch (e) {
          debugPrint('upsert_daily_gallons notice: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Transaction Record Submitted Successfully!'),
          ),
        );

        _userNameController.clear();
        _locationController.clear();
        _proofPhoto = null;

        // Switch to the Real-Time History Tab
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting record: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _quantityButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<Map<String, dynamic>> rawTransactions) {
    double totalGallons = 0;
    double totalCollection = 0;
    double totalCOD = 0;
    double totalGCash = 0;

    for (final tx in rawTransactions) {
      final gal = (tx['gallons'] as num?)?.toDouble() ?? 0.0;
      final price = (tx['price_per_gallon'] as num?)?.toDouble() ?? 180.0;
      final paid = (tx['amount_paid'] as num?)?.toDouble() ?? (gal * price);

      totalGallons += gal;
      totalCollection += paid;

      final notes = (tx['notes'] ?? '').toString().toLowerCase();
      final pm = (tx['payment_method'] ?? '').toString().toLowerCase();

      if (notes.contains('gcash') || pm.contains('gcash')) {
        totalGCash += paid;
      } else {
        totalCOD += paid;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REAL-TIME TRANSACTION SUMMARY',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _summaryStatPill('Total Gallons', '${totalGallons % 1 == 0 ? totalGallons.toInt() : totalGallons.toStringAsFixed(1)} Gal', Icons.water_drop_outlined, const Color(0xFF0284C7), const Color(0xFFF0F9FF)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryStatPill('Total Revenue', '₱${totalCollection.toStringAsFixed(2)}', Icons.monetization_on_outlined, const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _summaryStatPill('COD Collected', '₱${totalCOD.toStringAsFixed(2)}', Icons.payments_outlined, const Color(0xFFD97706), const Color(0xFFFFFBEB)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryStatPill('GCash Collected', '₱${totalGCash.toStringAsFixed(2)}', Icons.account_balance_wallet_outlined, const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStatPill(String title, String value, IconData icon, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(List<Map<String, dynamic>> rawTransactions) {
    if (rawTransactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No transaction records found in database.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'New transactions will automatically appear here in real time when submitted.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    _ensureMetadataLoaded(rawTransactions);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rawTransactions.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildSummaryCard(rawTransactions),
          );
        }

        final tx = rawTransactions[index - 1];

        // 1. Date & Time
        final dateRaw = tx['transaction_date'] ?? tx['created_at'];
        DateTime dateVal = DateTime.now();
        if (dateRaw != null) {
          dateVal = DateTime.tryParse(dateRaw.toString()) ?? DateTime.now();
        }
        final dateFormatted = '${formatLongDate(dateVal)} • ${formatTime12(dateVal)}';

        // 2. Name
        final customerId = tx['customer_id']?.toString();
        final rawName = tx['customer_name']?.toString();
        final customerName = (rawName != null && rawName.trim().isNotEmpty)
            ? rawName.trim()
            : (customerId != null ? (_profileNames[customerId] ?? 'Customer (${customerId.substring(0, 8)})') : 'Customer');

        // 3. Location
        final requestId = tx['delivery_request_id'];
        final orderMeta = _orderMap[requestId];
        final addressId = orderMeta?['address_id'];
        final addressMeta = _addressMap[addressId];

        String location = tx['address_line'] ?? tx['area'] ?? tx['location'] ?? '';
        if (location.isEmpty && addressMeta != null) {
          final label = addressMeta['label']?.toString() ?? '';
          final area = addressMeta['area']?.toString() ?? '';
          location = [label, area].where((s) => s.isNotEmpty).join(', ');
        }
        if (location.isEmpty) {
          location = 'Standard Delivery Address';
        }

        // 4. Order Type
        final rawWaterType = tx['water_type']?.toString() ?? orderMeta?['water_type']?.toString() ?? 'purified';
        final rawOrderType = tx['order_type']?.toString() ?? orderMeta?['order_type']?.toString() ?? 'refill';
        final orderTypeLabel = rawOrderType == 'exchange' ? 'Exchange Container' : 'Refill';

        // 5. Quantity
        final gallonsNum = (tx['gallons'] as num?)?.toDouble() ?? 0.0;
        final gallonsStr = '${gallonsNum % 1 == 0 ? gallonsNum.toInt() : gallonsNum.toStringAsFixed(1)} Gal';

        // 6. Price per Gallon
        final priceNum = (tx['price_per_gallon'] as num?)?.toDouble() ?? pricePerGallonFor(rawWaterType);
        final priceStr = '₱${priceNum.toStringAsFixed(2)} / gal';

        // 7. Total Price
        final amountPaid = (tx['amount_paid'] as num?)?.toDouble();
        final totalPrice = amountPaid != null && amountPaid > 0 ? amountPaid : (gallonsNum * priceNum);
        final totalPriceStr = '₱${totalPrice.toStringAsFixed(2)}';

        // 8. Payment Method
        final notesStr = (tx['notes'] ?? '').toString();
        final pmRaw = (tx['payment_method'] ?? '').toString().toLowerCase();

        String paymentMethod = 'Cash on Delivery';
        if (pmRaw.contains('gcash') || notesStr.toLowerCase().contains('gcash')) {
          paymentMethod = 'GCash';
        } else if (pmRaw.contains('card') || pmRaw.contains('credit') || notesStr.toLowerCase().contains('credit/debit')) {
          paymentMethod = 'Credit/Debit Card';
        } else if (pmRaw.isNotEmpty) {
          paymentMethod = tx['payment_method'].toString();
        }

        // 9. Status
        final statusRaw = (tx['status'] ?? 'paid').toString().toLowerCase();
        final isPaid = statusRaw == 'paid' || notesStr.contains('Paid');
        final statusBadgeText = isPaid ? 'Delivered - Paid' : 'Delivered - Credit';
        final statusBadgeColor = isPaid ? const Color(0xFF15803D) : const Color(0xFFB45309);
        final statusBadgeBg = isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Date & Status Badge (Flexible)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              dateFormatted,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBadgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusBadgeText,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusBadgeColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Name & Total Price Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total Price', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        Text(
                          totalPriceStr,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1E3A8A)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),

                // Grid Details: Order Type, Quantity, Price/Gal, Payment Method
                Row(
                  children: [
                    Expanded(
                      child: _infoCell('Order Type', orderTypeLabel, Icons.water_drop_outlined),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _infoCell('Quantity', gallonsStr, Icons.format_list_numbered),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _infoCell('Price / Gal', priceStr, Icons.sell_outlined),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _infoCell('Payment Method', paymentMethod, Icons.payment_outlined),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoCell(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordFormTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Customer Selection / Name
          const Text(
            'Customer',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          if (widget.stop != null)
            TextField(
              controller: _userNameController,
              readOnly: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedCustomerId,
              isExpanded: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              hint: const Text('Select Customer'),
              items: _customerProfiles.map((cust) {
                final id = cust['id'].toString();
                final name = (cust['full_name'] as String?)?.trim();
                final displayName = (name != null && name.isNotEmpty) ? name : (cust['email'] ?? 'Customer');
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(displayName, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedCustomerId = val;
                    final cust = _customerProfiles.firstWhere((c) => c['id'].toString() == val, orElse: () => {});
                    final name = cust['full_name'] as String?;
                    if (name != null) _userNameController.text = name;
                  });
                }
              },
            ),
          const SizedBox(height: 16),

          // 2. Delivery Location
          const Text(
            'Delivery Location',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _locationController,
            inputFormatters: [InputFormatters.alphanumeric],
            decoration: InputDecoration(
              hintText: 'e.g. Libertad Tungawan 12',
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.primary),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Water Type & Order Type Selectors
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Water Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text('Purified', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Order Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _orderType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'refill', child: Text('Refill', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'exchange', child: Text('Exchange', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _orderType = val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Quantity Counter
          const Text(
            'Quantity (Gallons)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_quantity x 5-Gal Container',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_waterType == 'mineral' ? 'Mineral Water' : 'Purified Water'} (${_orderType == 'exchange' ? 'Exchange' : 'Refill'})',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _quantityButton(Icons.remove, () {
                      setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1);
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    _quantityButton(Icons.add, () {
                      setState(() => _quantity++);
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Price Breakdown
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Price Per Gal:', style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF))),
                    Text('₱${_pricePerGallon.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, color: Color(0xFF93C5FD)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Price:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                    Text('₱${_totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6. Status & Payment Type Selectors
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Delivered - Paid', child: Text('Delivered - Paid', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Delivered - Credit', child: Text('Delivered - Credit', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Delivered (Active)', child: Text('Delivered (Active)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _status = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Cash on Delivery', child: Text('COD', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'GCash', child: Text('GCash', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Credit/Debit', child: Text('Credit/Debit', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentType = val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 7. Proof of Delivery (Camera Capture / Photo)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Proof of Delivery (Photo / Camera)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B)),
              ),
              if (_proofPhoto != null)
                TextButton(
                  onPressed: () => setState(() => _proofPhoto = null),
                  child: const Text('Remove Photo', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            ),
            child: _proofPhoto != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(
                      File(_proofPhoto!.path),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      child: IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                        onPressed: () => _takeProofPhoto(ImageSource.camera),
                        tooltip: 'Retake Photo',
                      ),
                    ),
                  ),
                ],
              ),
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined, size: 36, color: Color(0xFF94A3B8)),
                const SizedBox(height: 8),
                const Text(
                  'Capture Photo Proof of Delivery',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () => _takeProofPhoto(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () => _takeProofPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // SUBMIT BUTTON
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRecord,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
                  : const Text(
                'SUBMIT TRANSACTION RECORD',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.driverTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('TRANSACTION RECORDS'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            tabs: const [
              Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'History & Real-Time'),
              Tab(icon: Icon(Icons.add_circle_outline, size: 20), text: 'New Record'),
            ],
          ),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _transactionsStream,
          builder: (context, snapshot) {
            final rawTransactions = snapshot.data ?? [];

            return TabBarView(
              controller: _tabController,
              children: [
                _buildHistoryTab(rawTransactions),
                _buildRecordFormTab(),
              ],
            );
          },
        ),
      ),
    );
  }
}