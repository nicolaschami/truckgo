import 'dart:ui';

import 'package:flutter/material.dart';

import 'data/session_store.dart';
import 'login_page.dart';
import 'mock_vehicles.dart';
import 'permissions_page.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);

Color _statusColor(VehicleStatus status) => switch (status) {
      VehicleStatus.available => const Color(0xFF2E9D5B),
      VehicleStatus.inUse => const Color(0xFFE08A00),
      VehicleStatus.maintenance => const Color(0xFFD32F2F),
    };

class TruckSelectionPage extends StatefulWidget {
  const TruckSelectionPage({super.key, this.autoContinue = false});

  /// Goes straight on to the deliveries when the driver has a remembered
  /// truck (used after login). Coming back here lets the driver change it.
  final bool autoContinue;

  @override
  State<TruckSelectionPage> createState() => _TruckSelectionPageState();
}

class _TruckSelectionPageState extends State<TruckSelectionPage> {
  static const int _maxTrailers = 2;

  final _session = SessionStore.instance;

  bool _withTruck = true;
  Vehicle? _truck;
  final List<Vehicle> _trailers = [];
  String? _truckError;

  List<Vehicle> _allTrucks = [];
  List<Vehicle> _allTrailers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Vehicles from the database, with the driver's remembered truck selected.
  Future<void> _load() async {
    final trucks = await _session.vehicles(trucks: true);
    final trailers = await _session.vehicles(trucks: false);
    final link = await _session.truckLink();
    if (!mounted) return;

    Vehicle? find(List<Vehicle> list, String plate) {
      for (final v in list) {
        if (v.plate == plate) return v;
      }
      return null;
    }

    setState(() {
      _allTrucks = trucks;
      _allTrailers = trailers;
      if (link != null) {
        _truck = find(trucks, link.truckPlate);
        _trailers
          ..clear()
          ..addAll(link.trailerPlates
              .map((p) => find(trailers, p))
              .whereType<Vehicle>());
      }
      _loading = false;
    });

    if (widget.autoContinue && _truck != null) _continue();
  }

  // ---------------------------------------------------------------
  // PICKING
  // ---------------------------------------------------------------

  Future<Vehicle?> _pick({
    required String title,
    required List<Vehicle> source,
    required List<Vehicle> chosen,
  }) {
    return showModalBottomSheet<Vehicle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _VehiclePickerSheet(
        title: title,
        vehicles: source,
        chosen: chosen,
      ),
    );
  }

  Future<void> _pickTruck() async {
    if (_loading) return;
    final vehicle = await _pick(
      title: 'Select your truck',
      source: _allTrucks,
      chosen: _truck == null ? [] : [_truck!],
    );
    if (vehicle == null || !mounted) return;
    setState(() {
      _truck = vehicle;
      _truckError = null;
    });
  }

  Future<void> _addTrailer() async {
    if (_loading) return;
    final vehicle = await _pick(
      title: 'Select a trailer',
      source: _allTrailers,
      chosen: _trailers,
    );
    if (vehicle == null || !mounted) return;
    setState(() => _trailers.add(vehicle));
  }

  // ---------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------

  Future<void> _continue() async {
    if (_loading) return;
    if (_withTruck && _truck == null) {
      setState(() => _truckError = 'Please select your truck');
      return;
    }

    // Remember the link, so the next login skips this screen.
    // TODO: also tell dispatching which truck the driver is using.
    final truckPlate = _withTruck ? _truck!.plate : null;
    if (truckPlate != null) {
      await _session.saveTruckLink(
          truckPlate, _trailers.map((t) => t.plate).toList());
    } else {
      await _session.clearTruckLink();
    }
    if (!mounted) return;

    await openDeliveries(context, truckPlate);
  }

  Future<void> _logout() async {
    await _session.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),

                Image.asset('assets/images/truck_logo.png', height: 80),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.80),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.65),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Center(
                              child: Text(
                                'Choose Your Vehicle',
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.bold,
                                  color: _dark,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Center(
                              child: Text(
                                'Select what you are driving today',
                                style: TextStyle(fontSize: 14, color: _grey),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // MODE: truck / no truck
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _ModePill(
                                      icon: Icons.local_shipping_outlined,
                                      label: 'I have a truck',
                                      selected: _withTruck,
                                      onTap: () =>
                                          setState(() => _withTruck = true),
                                    ),
                                  ),
                                  Expanded(
                                    child: _ModePill(
                                      icon: Icons.directions_walk,
                                      label: 'No truck',
                                      selected: !_withTruck,
                                      onTap: () => setState(() {
                                        _withTruck = false;
                                        _truckError = null;
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),

                            if (_withTruck) ..._truckSection() else _noTruckInfo(),

                            const SizedBox(height: 22),

                            // BUTTONS
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: OutlinedButton(
                                      onPressed: _logout,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _blue,
                                        side: const BorderSide(
                                          color: _blue,
                                          width: 2,
                                        ),
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.logout, size: 20),
                                          SizedBox(width: 6),
                                          Text(
                                            'Log out',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _continue,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _blue,
                                        foregroundColor: Colors.white,
                                        elevation: 4,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Continue',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _truckSection() {
    return [
      const _SectionLabel('Truck'),
      const SizedBox(height: 8),
      _VehicleTile(
        vehicle: _truck,
        placeholder: 'Tap to choose a truck',
        icon: Icons.local_shipping_outlined,
        trailing: Icon(
          _truck == null ? Icons.search : Icons.swap_horiz,
          color: _grey,
        ),
        error: _truckError,
        onTap: _pickTruck,
      ),

      const SizedBox(height: 18),

      Row(
        children: [
          const _SectionLabel('Trailers'),
          const SizedBox(width: 6),
          Text(
            '(optional, max $_maxTrailers)',
            style: const TextStyle(fontSize: 12, color: _grey),
          ),
        ],
      ),
      const SizedBox(height: 8),

      for (final trailer in _trailers) ...[
        _VehicleTile(
          vehicle: trailer,
          placeholder: '',
          icon: Icons.rv_hookup,
          trailing: IconButton(
            icon: const Icon(Icons.close, color: _grey),
            onPressed: () => setState(() => _trailers.remove(trailer)),
          ),
          onTap: null,
        ),
        const SizedBox(height: 8),
      ],

      if (_trailers.length < _maxTrailers)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _addTrailer,
            icon: const Icon(Icons.add),
            label: const Text(
              'Add trailer',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: BorderSide(color: _blue.withOpacity(0.6), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _noTruckInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: _grey),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'You will continue without a truck. '
              'You can choose one later.',
              style: TextStyle(fontSize: 14, color: _dark),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// SMALL WIDGETS
// ---------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: _dark,
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : _grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : _grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.vehicle,
    required this.placeholder,
    required this.icon,
    required this.trailing,
    required this.onTap,
    this.error,
  });

  final Vehicle? vehicle;
  final String placeholder;
  final IconData icon;
  final Widget trailing;
  final VoidCallback? onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: error == null
                    ? null
                    : Border.all(color: const Color(0xFFD32F2F), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: _blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: v == null
                        ? Text(
                            placeholder,
                            style: const TextStyle(
                              fontSize: 15,
                              color: _grey,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.plate,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: _dark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${v.model}  •  ${v.detail}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                  ),
                  trailing,
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 5),
            child: Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F)),
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final VehicleStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// BOTTOM SHEET: searchable list of vehicles
// ---------------------------------------------------------------

class _VehiclePickerSheet extends StatefulWidget {
  const _VehiclePickerSheet({
    required this.title,
    required this.vehicles,
    required this.chosen,
  });

  final String title;
  final List<Vehicle> vehicles;
  final List<Vehicle> chosen;

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final items = widget.vehicles
        .where(
          (v) =>
              '${v.plate} ${v.model} ${v.detail}'.toLowerCase().contains(q),
        )
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _dark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // SEARCH
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by plate or model',
                  prefixIcon: const Icon(Icons.search, color: _grey),
                  filled: true,
                  fillColor: const Color(0xFFF2F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            // LIST
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'No vehicles found',
                        style: TextStyle(color: _grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final v = items[index];
                        final isChosen =
                            widget.chosen.any((c) => c.plate == v.plate);
                        final enabled = v.isAvailable && !isChosen;

                        return _PickerRow(
                          vehicle: v,
                          isChosen: isChosen,
                          enabled: enabled,
                          onTap: () => Navigator.of(context).pop(v),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.vehicle,
    required this.isChosen,
    required this.enabled,
    required this.onTap,
  });

  final Vehicle vehicle;
  final bool isChosen;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dimmed = !enabled && !isChosen;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: isChosen ? _blue.withOpacity(0.08) : const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    vehicle.isTruck
                        ? Icons.local_shipping_outlined
                        : Icons.rv_hookup,
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.plate,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _dark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${vehicle.model}  •  ${vehicle.detail}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: _grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isChosen)
                  const Icon(Icons.check_circle, color: _blue)
                else
                  _StatusChip(vehicle.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}