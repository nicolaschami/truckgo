import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'delivery_detail_page.dart';
import 'delivery_flow_page.dart';
import 'delivery_store.dart';
import 'mock_deliveries.dart';
import 'tracking/geofence_service.dart';
import 'tracking/test_data_export.dart';
import 'tracking/tracking_service.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);
const _green = Color(0xFF2E9D5B);

class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({super.key, this.truckPlate});

  /// Plate of the selected truck (null = "Access without truck")
  final String? truckPlate;

  @override
  State<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends State<DeliveriesPage> {
  final _store = DeliveryStore.instance;
  bool _showHistory = false;
  bool _loading = true;

  List<Delivery> get _current => _store.current;
  List<Delivery> get _history => _store.history;

  final _tracking = TrackingService.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _store.loadForTruck(widget.truckPlate).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });

    // GPS runs while this truck's deliveries are open (also in background)
    _tracking.addListener(_onStoreChanged);
    final truck = widget.truckPlate;
    if (truck != null) {
      _tracking.start(truck);
      GeofenceService.instance.start(); // plant and site zones
    }
  }

  // Back to truck selection, which keeps the remembered truck selected.
  void _changeTruck() => Navigator.of(context).maybePop();

  Future<void> _shareTestData() async {
    try {
      await TestDataExport.share(truckPlate: widget.truckPlate);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share the test data: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetTestData() async {
    await _store.resetTestData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test deliveries reloaded'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tracking.removeListener(_onStoreChanged);
    // Back to truck selection or logout: stop following the truck
    GeofenceService.instance.stop();
    _tracking.stop();
    super.dispose();
  }

  void _retryTracking() {
    final truck = widget.truckPlate;
    if (truck != null) _tracking.start(truck);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _open(Delivery delivery) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeliveryDetailPage(delivery: delivery),
      ),
    );
  }

  Future<void> _activate() async {
    final next = _current.first;
    final started = next.status != DeliveryStatus.assigned;

    // A delivery already in progress continues without asking again.
    final confirmed = started || (await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Activate delivery ${next.number}?'),
        content: Text(
          '${next.shipToName}\n'
          '${fmtTons(next.orderedTons)} of ${next.material}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Activate'),
          ),
        ],
      ),
    ) ?? false);

    if (!confirmed || !mounted) return;

    // Run the delivery from its current status to the signature
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => DeliveryFlowPage(delivery: next),
      ),
    );

    if (!mounted ||
        _store.byKey(next.key)?.status != DeliveryStatus.delivered) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Delivery ${next.number} completed'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _showHistory ? _history : _current;
    final hasTruck = widget.truckPlate != null;

    return Scaffold(
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
              // HEADER: logo + truck
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Image.asset('assets/images/truck_logo.png', height: 34),
                    const Spacer(),
                    if (kDebugMode && hasTruck) ...[
                      IconButton(
                        tooltip: 'Share test data',
                        icon: const Icon(Icons.share, color: Colors.white),
                        onPressed: _shareTestData,
                      ),
                      IconButton(
                        tooltip: 'Reset test data',
                        icon: const Icon(Icons.restart_alt, color: Colors.white),
                        onPressed: _resetTestData,
                      ),
                    ],
                    // Tap the truck to change it
                    Material(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _changeTruck,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.local_shipping_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.truckPlate ?? 'No truck',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.swap_horiz,
                                size: 16,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // TITLE
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Deliveries',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasTruck
                            ? '${_current.length} assigned to your truck'
                            : 'No truck selected',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      if (hasTruck) ...[
                        const SizedBox(height: 6),
                        _GpsIndicator(
                          tracking: _tracking,
                          onRetry: _retryTracking,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // TABS
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Tab(
                          label: 'Current',
                          selected: !_showHistory,
                          onTap: () => setState(() => _showHistory = false),
                        ),
                      ),
                      Expanded(
                        child: _Tab(
                          label: 'History',
                          selected: _showHistory,
                          onTap: () => setState(() => _showHistory = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // LIST
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : list.isEmpty
                    ? _EmptyState(
                        message: hasTruck
                            ? 'No deliveries here yet.'
                            : 'Select a truck to see your deliveries.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i == 1 && !_showHistory) const _PlannedDivider(),
                            _DeliveryCard(
                              delivery: list[i],
                              tag: _tagFor(list[i], i),
                              onTap: () => _open(list[i]),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),

              // ACTIVATE BUTTON (only on the Current tab)
              if (!_showHistory && !_loading && _current.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _activate,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        _current.first.status == DeliveryStatus.assigned
                            ? 'Activate current delivery'
                            : 'Continue current delivery',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            Colors.white.withOpacity(0.25),
                        disabledForegroundColor: Colors.white70,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _tagFor(Delivery d, int index) =>
      (d.status == DeliveryStatus.assigned && index == 0)
          ? ('Next', _green)
          : (d.status.label, deliveryStatusColor(d.status));
}

// ---------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: selected ? _blue : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannedDivider extends StatelessWidget {
  const _PlannedDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(color: Colors.white.withOpacity(0.35), height: 1),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
      child: Row(
        children: [
          line,
          const SizedBox(width: 10),
          Icon(Icons.schedule, size: 16, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 6),
          Text(
            'Planned',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 10),
          line,
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.delivery,
    required this.tag,
    required this.onTap,
  });

  final Delivery delivery;
  final (String, Color) tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = delivery;

    return Material(
      color: Colors.white.withOpacity(0.95),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: tag.$2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: _dark,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'DELIVERY ${d.number}',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: _dark,
                            ),
                          ),
                          const Spacer(),
                          DeliveryStatusChip(label: tag.$1, color: tag.$2),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.shipToName,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: _dark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  d.shipToAddress,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                fmtTime(d.scheduled),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: _dark,
                                ),
                              ),
                              Text(
                                fmtDay(d.scheduled),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 16,
                            color: _grey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${d.material}  •  ${fmtTons(d.orderedTons)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _grey,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: _grey,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "GPS on / off" line, so the driver (and testers) can see that the
/// truck is being followed. Tap it to retry when it is off.
class _GpsIndicator extends StatelessWidget {
  const _GpsIndicator({required this.tracking, required this.onRetry});

  final TrackingService tracking;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final last = tracking.lastPosition;
    final (Color color, String text) = switch (tracking) {
      _ when tracking.problem != null => (
          const Color(0xFFFF8A80),
          'GPS off – ${tracking.problem}. Tap to retry',
        ),
      _ when !tracking.isRunning => (Colors.white54, 'GPS off'),
      _ when last == null => (const Color(0xFFFFD180), 'GPS starting…'),
      _ => (
          const Color(0xFF69F0AE),
          'GPS on  •  ±${last.accuracy.round()} m  •  ${fmtTime(last.timestamp.toLocal())}',
        ),
    };

    return GestureDetector(
      onTap: tracking.problem != null ? onRetry : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.6),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}