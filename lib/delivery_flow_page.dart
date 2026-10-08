import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'delivery_store.dart';
import 'widgets/delivery_info.dart';
import 'loading_truck_animation.dart';
import 'mock_deliveries.dart';
import 'tracking/arrival_notifications.dart';
import 'tracking/geofence_service.dart';
import 'tracking/tracking_service.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);
const _green = Color(0xFF2E9D5B);
const _paper = Color(0xFFF2F5F9);
const _orange = Color(0xFFE8890C);

const _unloadDuration = Duration(seconds: 4);

enum _Step {
  loadingPoint,
  loading,
  customerSite,
  deliveryNotes,
  unloading,
  activities,
  signature,
  done,
}

class _Activity {
  const _Activity(this.key, this.label, this.hint, this.unit);

  final String key;
  final String label;
  final String hint;
  final String? unit; // null = just a tick box
}

const _activities = [
  _Activity('chute', 'Chute used', 'You used the chute when tipping.', null),
  _Activity('daywork', 'Daywork', 'You waited while the truck was unloaded.', 'min'),
  _Activity('waiting', 'Waiting time', 'You arrived and had to wait to tip.', 'min'),
  _Activity('extraMinutes', 'Additional minutes', 'Extra time to leave the site.', 'min'),
  _Activity('returned', 'Estimated returned quantity', 'Weight you are taking back.', 't'),
  _Activity('extraKm', 'Additional km', 'Haulage zone differs from the distance driven.', 'km'),
];

class DeliveryFlowPage extends StatefulWidget {
  const DeliveryFlowPage({super.key, required this.delivery});

  final Delivery delivery;

  @override
  State<DeliveryFlowPage> createState() => _DeliveryFlowPageState();
}

class _DeliveryFlowPageState extends State<DeliveryFlowPage> {
  final _store = DeliveryStore.instance;

  late _Step _step;
  Timer? _timer;

  bool _unloadDone = false;
  bool _cancelShown = false;

  final _driverNotes = TextEditingController();
  final _customerName = TextEditingController();
  final _customerNotes = TextEditingController();

  final Map<String, bool> _actOn = {};
  final Map<String, TextEditingController> _actValue = {};

  bool _hasSignature = false;
  bool _accepted = false;
  final _signatureKey = GlobalKey<_SignaturePadState>();

  /// Always the latest version from the store (weights, status).
  Delivery get d => _store.byKey(widget.delivery.key) ?? widget.delivery;

  String get _conveyance => '88${d.number}';

  @override
  void initState() {
    super.initState();
    for (final a in _activities) {
      _actOn[a.key] = false;
      _actValue[a.key] = TextEditingController();
    }
    _step = _stepFor(d.status);
    _unloadDone = d.status == DeliveryStatus.unloading;
    _store.addListener(_onStoreChanged);
  }

  /// The step to resume at, so a delivery can be closed and reopened.
  _Step _stepFor(DeliveryStatus status) => switch (status) {
        DeliveryStatus.assigned || DeliveryStatus.atPlant => _Step.loadingPoint,
        DeliveryStatus.loading => _Step.loading,
        DeliveryStatus.inTransit => _Step.customerSite,
        DeliveryStatus.arrivedAtSite => _Step.deliveryNotes,
        DeliveryStatus.unloading => _Step.unloading,
        DeliveryStatus.delivered || DeliveryStatus.cancelled => _Step.done,
      };

  // Weights and cancellations from dispatching move the flow on their own.
  void _onStoreChanged() {
    if (!mounted) return;
    final status = d.status;

    if (status == DeliveryStatus.cancelled) {
      _showCancelled();
      return;
    }

    // A status set from outside this screen (weights, the arrival reminder)
    // moves the flow forward, never back.
    setState(() {
      final target = _stepFor(status);
      if (target.index > _step.index) _step = target;
    });
  }

  Future<void> _showCancelled() async {
    if (_cancelShown) return;
    _cancelShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delivery cancelled'),
        content: Text(
          'Dispatching cancelled delivery ${d.number}. '
          'Contact the planning team if you have questions.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _timer?.cancel();
    _driverNotes.dispose();
    _customerName.dispose();
    _customerNotes.dispose();
    for (final c in _actValue.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------

  Future<void> _confirmArrival() async {
    final arrived = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Have you arrived at the customer site?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (arrived == true && mounted) {
      // Confirmed here: the geofence reminder is no longer needed
      GeofenceService.instance.dismissReminder();
      ArrivalNotifications.cancel(d);
      _store.setStatus(d.key, DeliveryStatus.arrivedAtSite,
          trigger: StatusTrigger.driver);
      setState(() => _step = _Step.deliveryNotes);
    }
  }

  void _startUnloading() {
    _store.setStatus(d.key, DeliveryStatus.unloading,
        trigger: StatusTrigger.driver);
    setState(() {
      _step = _Step.unloading;
      _unloadDone = false;
    });
    _timer = Timer(_unloadDuration, () {
      if (!mounted) return;
      setState(() => _unloadDone = true);
    });
  }

  void _goToSignature() {
    // every ticked activity with a unit needs a value
    for (final a in _activities) {
      if (_actOn[a.key] == true &&
          a.unit != null &&
          _actValue[a.key]!.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enter a value for "${a.label}"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    setState(() => _step = _Step.signature);
  }

  List<String> _activitySummary() {
    final lines = <String>[];
    for (final a in _activities) {
      if (_actOn[a.key] != true) continue;
      final value = _actValue[a.key]!.text.trim();
      lines.add(a.unit == null ? a.label : '${a.label}: $value ${a.unit}');
    }
    return lines;
  }

  bool get _canSave =>
      _customerName.text.trim().isNotEmpty && _hasSignature && _accepted;

  String? _textOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  // Saved in SQLite as unsent; the API client will send it to dispatching.
  Future<void> _save() async {
    final signature = await _signatureKey.currentState?.toPng();
    await _store.completeDelivery(
      d.key,
      customerName: _customerName.text.trim(),
      customerNotes: _textOrNull(_customerNotes),
      driverNotes: _textOrNull(_driverNotes),
      signaturePng: signature,
      activities: [
        for (final a in _activities)
          if (_actOn[a.key] == true)
            ActivityRecord(
              code: a.key,
              value: a.unit == null ? null : _actValue[a.key]!.text.trim(),
              unit: a.unit,
            ),
      ],
    );
    if (mounted) setState(() => _step = _Step.done);
  }

  void _finish() => Navigator.of(context).pop();

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this delivery?'),
        content: const Text(
          'You can continue it later from My Deliveries. Notes, activities '
          'and the signature on this screen are not kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------
  // SHELL: top bar + progress + white sheet
  // ---------------------------------------------------------------

  int get _progressIndex => switch (_step) {
        _Step.loadingPoint => 0,
        _Step.loading => 1,
        _Step.customerSite => 2,
        _Step.deliveryNotes => 3,
        _Step.unloading => 4,
        _Step.activities => 5,
        _Step.signature => 6,
        _Step.done => 6,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_step == _Step.done) {
          _finish();
        } else {
          _confirmLeave();
        }
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B57A1), Color(0xFF063470)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _step == _Step.done
                            ? _finish
                            : _confirmLeave,
                      ),
                      Expanded(
                        child: Text(
                          'Delivery ${d.number}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // PROGRESS
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Container(
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i <= _progressIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // WHITE SHEET
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: _paper,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(26)),
                    ),
                    child: _body(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.loadingPoint:
        return _loadingPoint();
      case _Step.loading:
        return _loadingStep();
      case _Step.customerSite:
        return _customerSite();
      case _Step.deliveryNotes:
        return _deliveryNotes();
      case _Step.unloading:
        return _unloading();
      case _Step.activities:
        return _activitiesStep();
      case _Step.signature:
        return _signature();
      case _Step.done:
        return _doneStep();
    }
  }

  // ---------------------------------------------------------------
  // STEPS
  // ---------------------------------------------------------------

  Widget _loadingPoint() {
    final atPlant = d.status == DeliveryStatus.atPlant;

    return _Page(
      title: '1. Loading point',
      child: Column(
        children: [
          _Banner(
            icon: atPlant ? Icons.scale_outlined : Icons.factory_outlined,
            text: atPlant
                ? 'Drive onto the weighbridge. Loading starts with the 1st '
                    'weight.'
                : 'Drive to ${d.shippingPoint}. Arrival is detected '
                    'automatically.',
          ),
          const SizedBox(height: 10),
          _WeightsCard(
            delivery: d,
            waitingText: atPlant
                ? 'Waiting for the 1st weight'
                : 'Waiting for arrival at the plant',
          ),
          const SizedBox(height: 10),
          _InfoGrid([
            InfoItem('Shipping point', d.shippingPoint, Icons.factory_outlined),
            InfoItem('Load line', d.number, Icons.tag),
            InfoItem('Material', d.material, Icons.layers_outlined),
            InfoItem('Quantity', fmtTons(d.orderedTons),
                Icons.inventory_2_outlined),
          ]),
          _TestTools(delivery: d),
        ],
      ),
    );
  }

  Widget _loadingStep() {
    return _Page(
      title: '2. Loading truck',
      child: Column(
        children: [
          // The animation at a smaller size
          const SizedBox(
            height: 120,
            child: FittedBox(
              child: TruckLoadAnimation(
                targetTons: 0,
                untilStopped: true,
                duration: Duration(seconds: 8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _WeightsCard(
            delivery: d,
            waitingText: 'Loading — waiting for the 2nd weight',
          ),
          const SizedBox(height: 10),
          _InfoGrid([
            InfoItem('Material', d.material, Icons.layers_outlined),
            InfoItem('Order quantity', fmtTons(d.orderedTons),
                Icons.inventory_2_outlined),
          ]),
          _TestTools(delivery: d),
        ],
      ),
    );
  }

  Widget _customerSite() {
    final eta = DateTime.now()
        .add(Duration(minutes: (d.distanceKm * 1.4).round()));

    return _Page(
      title: '3. Customer site',
      actions: Row(
        children: [
          Expanded(child: _primary('I have arrived', _confirmArrival)),
          const SizedBox(width: 10),
          Expanded(
            child: _secondary(
                'Open navigation', () => openNavigation(context, d),
                icon: Icons.navigation_outlined),
          ),
        ],
      ),
      child: Column(
        children: [
          _customerSiteFields(eta),
          _TestTools(delivery: d),
        ],
      ),
    );
  }

  Widget _customerSiteFields(DateTime eta) {
    return FieldRows([
      [
        InfoItem('Customer name', d.soldToName, Icons.business_outlined),
        InfoItem('Conveyance number', _conveyance, Icons.receipt_long_outlined),
      ],
      [siteItem(context, d, navigate: true)],
      [siteContactItem(context, d)],
      [
        InfoItem('Order quantity', fmtTons(d.orderedTons),
            Icons.inventory_2_outlined),
        InfoItem('Distance', '${d.distanceKm.toStringAsFixed(1)} km',
            Icons.route_outlined),
      ],
      [
        InfoItem('Tare', fmtWeight(d.tareTons), Icons.scale_outlined),
        InfoItem('Gross', fmtWeight(d.grossTons), Icons.scale_outlined),
        InfoItem('Net', fmtWeight(d.loadedTons), Icons.scale_outlined),
      ],
      [
        InfoItem('Estimated arrival', fmtTime(eta), Icons.schedule),
        InfoItem('Requested site time',
            '${fmtDay(d.scheduled)}, ${fmtTime(d.scheduled)}',
            Icons.event_outlined),
      ],
      [
        InfoItem('Notes', d.notes ?? 'No notes have been included',
            Icons.sticky_note_2_outlined),
      ],
    ]);
  }

  Widget _deliveryNotes() {
    return _Page(
      title: '4. Delivery notes',
      actions: _primary('Unload truck', _startUnloading,
          icon: Icons.download_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldRows([
            [
              InfoItem('Customer name', d.soldToName, Icons.business_outlined),
              InfoItem('Conveyance number', _conveyance,
                  Icons.receipt_long_outlined),
            ],
            [siteItem(context, d)],
            [siteContactItem(context, d)],
            [InfoItem('Material', d.material, Icons.layers_outlined)],
            [
              InfoItem('Order quantity', fmtTons(d.orderedTons),
                  Icons.inventory_2_outlined),
              InfoItem('Delivered quantity', fmtWeight(d.loadedTons),
                  Icons.scale_outlined),
            ],
            [
              InfoItem('Delivery note instructions',
                  d.notes ?? 'No notes have been included',
                  Icons.assignment_outlined),
            ],
          ]),
          const SizedBox(height: 14),
          const _Label('Driver notes'),
          const SizedBox(height: 6),
          _input(
            _driverNotes,
            'Write anything the planning team should know',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _unloading() {
    return _Page(
      title: '5. Unloading truck',
      actions: _unloadDone
          ? Row(
              children: [
                Expanded(
                  child: _secondary(
                    'Finish and report',
                    () => setState(() => _step = _Step.activities),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _primary(
                    'Finish',
                    () => setState(() => _step = _Step.signature),
                  ),
                ),
              ],
            )
          : null,
      child: _unloadDone
          ? const _Waiting(
              icon: Icons.check_circle,
              iconColor: _green,
              busy: false,
              text: 'Unloading complete',
              sub: 'Tap Finish if you have nothing to report, or '
                  '"Finish and report" to add extra activities.',
            )
          : Center(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  TruckLoadAnimation(
                    targetTons: d.loadedTons ?? d.orderedTons,
                    unloading: true,
                    duration: _unloadDuration,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Please wait while the truck is unloading',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _dark,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _activitiesStep() {
    return _Page(
      title: '6. Additional activities',
      actions: Row(
        children: [
          Expanded(
            child: _secondary(
              'Back',
              () => setState(() => _step = _Step.unloading),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _primary('Customer signature', _goToSignature)),
        ],
      ),
      child: Column(
        children: [
          const _Banner(
            icon: Icons.info_outline,
            text: 'Tick what applies. These will be shown to the customer '
                'before they sign.',
          ),
          const SizedBox(height: 12),
          for (final a in _activities) ...[
            _ActivityTile(
              activity: a,
              checked: _actOn[a.key] ?? false,
              controller: _actValue[a.key]!,
              onChanged: (v) => setState(() => _actOn[a.key] = v),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _signature() {
    final extras = _activitySummary();

    return _Page(
      title: '7. Customer signature',
      actions: Row(
        children: [
          Expanded(
            child: _secondary(
              'Back to report',
              () => setState(() => _step = _Step.activities),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _primary('Save', _canSave ? _save : null)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Closed by default so the signature fits on screen
          Collapsible(
            title: 'Delivery summary',
            summary: 'Order ${d.orderNumber}  •  '
                '${fmtWeight(d.loadedTons)} ${d.material}',
            child: FieldRows([
              [
                InfoItem('Order number', d.orderNumber, Icons.tag),
                InfoItem('Conveyance number', _conveyance,
                    Icons.receipt_long_outlined),
              ],
              [InfoItem('Material', d.material, Icons.layers_outlined)],
              [
                InfoItem('Loaded', fmtWeight(d.loadedTons), Icons.scale_outlined),
                InfoItem('Tare', fmtWeight(d.tareTons), Icons.scale_outlined),
                InfoItem('Gross', fmtWeight(d.grossTons), Icons.scale_outlined),
              ],
            ]),
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Fields([('Additional activities', extras.join('\n'))]),
          ],
          const SizedBox(height: 16),
          const _Label('Customer name'),
          const SizedBox(height: 6),
          _input(
            _customerName,
            'Name of the person signing',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _SignaturePad(
            key: _signatureKey,
            onChanged: (hasInk) => setState(() => _hasSignature = hasInk),
          ),
          const SizedBox(height: 10),
          // Confirmation first, then the optional notes
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _accepted = !_accepted),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _accepted
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: _accepted ? _blue : _grey,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'The customer confirms the delivery was received as '
                      'described above.',
                      style: TextStyle(fontSize: 13.5, color: _dark),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _Label('Customer notes'),
          const SizedBox(height: 6),
          _input(_customerNotes, 'Optional', maxLines: 2),
        ],
      ),
    );
  }

  Widget _doneStep() {
    final extras = _activitySummary();

    return _Page(
      title: 'Delivery completed',
      actions: _primary('Back to deliveries', _finish),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.check_circle, size: 84, color: _green),
          const SizedBox(height: 16),
          _Fields([
            ('Delivery', '${d.number}  •  ${d.shipToName}'),
            ('Delivered', '${fmtWeight(d.loadedTons)} of ${d.material}'),
            ('Signed by', _customerName.text.trim()),
            if (extras.isNotEmpty) ('Additional activities', extras.join('\n')),
          ]),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // SMALL HELPERS
  // ---------------------------------------------------------------

  Widget _primary(String label, VoidCallback? onTap, {IconData? icon}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB8C4D2),
          disabledForegroundColor: Colors.white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _secondary(String label, VoidCallback onTap, {IconData? icon}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _blue,
          side: const BorderSide(color: _blue, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

// ---------------------------------------------------------------
// LAYOUT WIDGETS
// ---------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.actions});

  final String title;
  final Widget child;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
        if (actions != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: actions,
            ),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: _dark,
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields(this.items);

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0x1A102A43)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].$1,
                    style: const TextStyle(fontSize: 12, color: _grey),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _dark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, color: _dark),
            ),
          ),
        ],
      ),
    );
  }
}

/// The weighbridge at a glance: what the app is waiting for, then the
/// 1st weight, 2nd weight and net load side by side.
class _WeightsCard extends StatelessWidget {
  const _WeightsCard({required this.delivery, required this.waitingText});

  final Delivery delivery;
  final String waitingText;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    // The tile currently expected from dispatching, if any
    final waitingTare = d.status == DeliveryStatus.atPlant;
    final waitingGross = d.status == DeliveryStatus.loading;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  waitingText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _dark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _WeightTile(
                  label: '1st weight',
                  value: d.tareTons,
                  waiting: waitingTare,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WeightTile(
                  label: '2nd weight',
                  value: d.grossTons,
                  waiting: waitingGross,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WeightTile(label: 'Net load', value: d.loadedTons),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightTile extends StatelessWidget {
  const _WeightTile({
    required this.label,
    required this.value,
    this.waiting = false,
  });

  final String label;
  final double? value;
  final bool waiting; // highlighted: this is the weight expected next

  @override
  Widget build(BuildContext context) {
    final received = value != null;
    final color = received ? _green : (waiting ? _blue : _grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: received || waiting ? 0.09 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: waiting ? Border.all(color: _blue, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11.5, color: _grey),
                ),
              ),
              if (received) const Icon(Icons.check_circle, size: 14, color: _green),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            received ? value!.toStringAsFixed(2) : '—',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: received ? _dark : _grey,
            ),
          ),
          const Text('t', style: TextStyle(fontSize: 11, color: _grey)),
        ],
      ),
    );
  }
}

/// Short facts in two columns, to keep the step compact.
class _InfoGrid extends StatelessWidget {
  const _InfoGrid(this.items);

  final List<InfoItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final item in items)
                SizedBox(width: cell, child: FieldCell(item)),
            ],
          );
        },
      ),
    );
  }
}

/// Debug builds only: buttons that play the dispatching system and the plant
/// geofence, until the API and background tracking exist.
class _TestTools extends StatelessWidget {
  const _TestTools({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    // Rebuilt on every GPS position, for the live distances
    return ListenableBuilder(
      listenable: TrackingService.instance,
      builder: (context, _) => _content(),
    );
  }

  Widget _content() {
    final store = DeliveryStore.instance;
    final geofence = GeofenceService.instance;
    final d = delivery;
    const tare = 14.20;
    final here = TrackingService.instance.lastPosition;

    String zone(String name, double? distance, double radius) {
      if (distance == null) return '$name: no GPS yet';
      final inside = distance <= radius ? 'INSIDE' : 'outside';
      return '$name ${distance.round()} m (zone ${radius.round()} m, $inside)';
    }

    Widget button(String label, VoidCallback onTap) => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: _orange,
            side: const BorderSide(color: _orange),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(fontSize: 12.5),
          ),
          child: Text(label),
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TEST TOOLS — plays dispatching (debug only)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: _orange,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (d.status == DeliveryStatus.assigned)
                button(
                  'Arrive at plant',
                  () => store.setStatus(d.key, DeliveryStatus.atPlant,
                      trigger: StatusTrigger.geofence),
                ),
              if (d.tareTons == null)
                button(
                  'Send 1st weight',
                  () => store.receiveWeights(d.key, tareTons: tare),
                ),
              if (d.tareTons != null && d.grossTons == null)
                button(
                  'Send 2nd weight',
                  () => store.receiveWeights(
                    d.key,
                    grossTons: d.tareTons! + d.orderedTons + 0.04,
                  ),
                ),
              // Geofence tests on foot: move the zone to where you stand
              if (here != null && d.status == DeliveryStatus.assigned)
                button(
                  'Plant = here',
                  () => store.debugMoveGeofence(d.key,
                      plant: true,
                      latitude: here.latitude,
                      longitude: here.longitude),
                ),
              if (here != null &&
                  d.status.index <= DeliveryStatus.inTransit.index)
                button(
                  'Site = here',
                  () => store.debugMoveGeofence(d.key,
                      plant: false,
                      latitude: here.latitude,
                      longitude: here.longitude),
                ),
              button(
                'Cancel delivery',
                () => store.setStatus(d.key, DeliveryStatus.cancelled,
                    trigger: StatusTrigger.dispatch),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Live distances to the two zones
          Text(
            '${zone('Plant', geofence.distanceToPlantM(d), geofence.plantRadiusM(d))}\n'
            '${zone('Site', geofence.distanceToSiteM(d), geofence.siteRadiusM(d))}'
            '${here == null ? '' : '\nGPS ±${here.accuracy.round()} m'}',
            style: const TextStyle(fontSize: 11.5, color: _dark),
          ),
          // Small zones to test around the house
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Small test zones (15 m)',
                  style: TextStyle(fontSize: 12.5, color: _orange),
                ),
              ),
              Switch(
                value: geofence.smallTestZones,
                activeThumbColor: _orange,
                onChanged: (on) => geofence.setSmallTestZones(on),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.icon,
    required this.text,
    this.sub,
    this.iconColor = _blue,
    this.busy = true,
  });

  final IconData icon;
  final String text;
  final String? sub;
  final Color iconColor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: iconColor),
            ),
            const SizedBox(height: 24),
            if (busy)
              const SizedBox(
                width: 160,
                child: LinearProgressIndicator(minHeight: 5),
              ),
            if (busy) const SizedBox(height: 18),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _dark,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 8),
              Text(
                sub!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: _grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.activity,
    required this.checked,
    required this.controller,
    required this.onChanged,
  });

  final _Activity activity;
  final bool checked;
  final TextEditingController controller;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: checked ? _blue.withOpacity(0.6) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => onChanged(!checked),
            child: Row(
              children: [
                Icon(
                  checked ? Icons.check_box : Icons.check_box_outline_blank,
                  color: checked ? _blue : _grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _dark,
                        ),
                      ),
                      Text(
                        activity.hint,
                        style: const TextStyle(fontSize: 12, color: _grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (checked && activity.unit != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Value',
                suffixText: activity.unit,
                isDense: true,
                filled: true,
                fillColor: _paper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// SIGNATURE PAD
// ---------------------------------------------------------------

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({super.key, required this.onChanged});

  /// true when something is drawn, false after "Clear"
  final ValueChanged<bool> onChanged;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];

  void _clear() {
    setState(() => _strokes.clear());
    widget.onChanged(false);
  }

  /// The signature as a PNG, cropped to the ink (null when empty).
  Future<Uint8List?> toPng() async {
    final points = _strokes.expand((s) => s);
    if (points.isEmpty) return null;

    const margin = 8.0;
    var bounds = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
    }
    bounds = bounds.inflate(margin);

    const scale = 2.0; // sharper image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top)
      ..drawRect(bounds, Paint()..color = Colors.white);
    _InkPainter(_strokes).paint(canvas, bounds.size);

    final image = await recorder.endRecording().toImage(
          (bounds.width * scale).ceil(),
          (bounds.height * scale).ceil(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _Label('Customer signature'),
            const Spacer(),
            TextButton.icon(
              onPressed: _strokes.isEmpty ? null : _clear,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        Container(
          height: 120, // compact: name, signature and checkbox fit together
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _grey.withOpacity(0.35)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            // "Eager" wins the gesture right away, so the page does not
            // scroll while the customer is signing.
            child: RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                  (instance) {},
                ),
              },
              child: Listener(
                onPointerDown: (event) {
                  setState(() => _strokes.add([event.localPosition]));
                  widget.onChanged(true);
                },
                onPointerMove: (event) {
                  if (_strokes.isEmpty) return;
                  setState(() => _strokes.last.add(event.localPosition));
                },
                child: Stack(
                  children: [
                    if (_strokes.isEmpty)
                      const Center(
                        child: Text(
                          'Sign here',
                          style: TextStyle(fontSize: 16, color: Color(0xFFB0BCCB)),
                        ),
                      ),
                    CustomPaint(
                      painter: _InkPainter(_strokes),
                      size: Size.infinite,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _dark
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          1.4,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}