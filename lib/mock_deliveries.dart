// Deliveries and their statuses (see docs/system-design.md).
// The mock lists at the bottom will be replaced by data from the API.

/// Delivery statuses, in order. A delivery only moves forward through this
/// list (steps may be skipped, e.g. a missed plant geofence), except
/// [cancelled], which dispatching can set at any time before [delivered].
enum DeliveryStatus {
  assigned('Assigned'), // dispatching assigned it to the truck
  atPlant('At plant'), // truck entered the plant geofence
  loading('Loading'), // 1st weight (tare) received from dispatching
  inTransit('In transit'), // 2nd weight (gross) received from dispatching
  arrivedAtSite('Arrived at site'), // driver tapped "I have arrived"
  unloading('Unloading'), // driver tapped "Unload truck"
  delivered('Delivered'), // customer signed
  cancelled('Cancelled'); // set by dispatching

  const DeliveryStatus(this.label);

  final String label;

  bool get isFinished => this == delivered || this == cancelled;
}

String deliveryKey(String number, String plantCode) => '$plantCode/$number';

/// Who caused a status change. Sent to dispatching with every change.
enum StatusTrigger { dispatch, geofence, driver }

/// One status change, kept to be sent to dispatching.
class StatusEvent {
  const StatusEvent({
    required this.deliveryNumber,
    required this.plantCode,
    required this.status,
    required this.time,
    required this.trigger,
    this.latitude,
    this.longitude,
  });

  final String deliveryNumber;
  final String plantCode;
  final DeliveryStatus status;
  final DateTime time;
  final StatusTrigger trigger;
  final double? latitude; // filled once background tracking is in place
  final double? longitude;
}

class Delivery {
  const Delivery({
    required this.number,
    required this.orderNumber,
    required this.soldToName,
    required this.soldToCode,
    required this.shipToName,
    required this.shipToAddress,
    required this.latitude,
    required this.longitude,
    required this.siteContact,
    required this.plantCode,
    required this.shippingPoint,
    required this.plantLatitude,
    required this.plantLongitude,
    required this.material,
    required this.orderedTons,
    required this.scheduled,
    required this.windowStart,
    required this.windowEnd,
    required this.distanceKm,
    this.truckPlate,
    this.siteGeofenceRadiusM = defaultGeofenceRadiusM,
    this.plantGeofenceRadiusM = defaultGeofenceRadiusM,
    this.tareTons,
    this.grossTons,
    this.notes,
    this.status = DeliveryStatus.assigned,
  });

  static const defaultGeofenceRadiusM = 200.0;

  final String number; // delivery number (unique together with plantCode)
  final String orderNumber;
  final String soldToName; // the customer who bought the material
  final String soldToCode;
  final String shipToName; // where the material is delivered
  final String shipToAddress;
  final double latitude; // delivery site position (for navigation)
  final double longitude;
  final String siteContact;
  final String plantCode; // plant id (part of the delivery key)
  final String shippingPoint; // plant name, where the truck loads
  final double plantLatitude; // shipping point position (route start)
  final double plantLongitude;
  final String material;
  final double orderedTons;
  final DateTime scheduled;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double distanceKm;
  final String? truckPlate; // truck the delivery is assigned to
  final double siteGeofenceRadiusM;
  final double plantGeofenceRadiusM;
  final double? tareTons; // 1st weight, from dispatching (null = not yet)
  final double? grossTons; // 2nd weight, from dispatching (null = not yet)
  final String? notes;
  final DeliveryStatus status;

  /// Unique key in the whole system: delivery number + plant.
  String get key => deliveryKey(number, plantCode);

  /// Net load, known once both weights have arrived.
  double? get loadedTons =>
      tareTons != null && grossTons != null ? grossTons! - tareTons! : null;

  Delivery copyWith({
    DeliveryStatus? status,
    double? tareTons,
    double? grossTons,
    String? truckPlate,
  }) {
    return Delivery(
      number: number,
      orderNumber: orderNumber,
      soldToName: soldToName,
      soldToCode: soldToCode,
      shipToName: shipToName,
      shipToAddress: shipToAddress,
      latitude: latitude,
      longitude: longitude,
      siteContact: siteContact,
      plantCode: plantCode,
      shippingPoint: shippingPoint,
      plantLatitude: plantLatitude,
      plantLongitude: plantLongitude,
      material: material,
      orderedTons: orderedTons,
      scheduled: scheduled,
      windowStart: windowStart,
      windowEnd: windowEnd,
      distanceKm: distanceKm,
      truckPlate: truckPlate ?? this.truckPlate,
      siteGeofenceRadiusM: siteGeofenceRadiusM,
      plantGeofenceRadiusM: plantGeofenceRadiusM,
      tareTons: tareTons ?? this.tareTons,
      grossTons: grossTons ?? this.grossTons,
      notes: notes,
      status: status ?? this.status,
    );
  }
}

// ---------------------------------------------------------------
// Small formatting helpers (no extra package needed)
// ---------------------------------------------------------------

final DateTime _now = DateTime.now();

DateTime _day(int offset, int hour, int minute) =>
    DateTime(_now.year, _now.month, _now.day + offset, hour, minute);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String fmtDay(DateTime d) {
  final today = DateTime.utc(_now.year, _now.month, _now.day);
  final that = DateTime.utc(d.year, d.month, d.day);
  final diff = that.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${d.day} ${_months[d.month - 1]}';
}

String fmtTons(double v) => '${v.toStringAsFixed(2)} t';

/// A weight that may not have arrived yet from dispatching.
String fmtWeight(double? v) => v == null ? '—' : fmtTons(v);

// ---------------------------------------------------------------
// MOCK DATA
// ---------------------------------------------------------------

// Plant positions. These are placeholders near the delivery sites:
// replace them with the real plant coordinates.
const _quarryNorthLat = 52.5545, _quarryNorthLng = -1.5260;
const _quarrySouthLat = 52.2600, _quarrySouthLng = -1.3935;

// Current + planned deliveries (the first one is the next load)
final List<Delivery> mockDeliveries = [
  Delivery(
    number: '422211',
    orderNumber: '30771239',
    soldToName: 'Northgate Construction Ltd',
    soldToCode: '100245',
    shipToName: 'Riverside Arena Works',
    shipToAddress: 'Arena Way, Coventry',
    latitude: 52.4486,
    longitude: -1.4955,
    siteContact: 'Dan Whitfield  •  +44 7700 900123',
    plantCode: 'QN2',
    shippingPoint: 'Quarry North - Plant 2',
    plantLatitude: _quarryNorthLat,
    plantLongitude: _quarryNorthLng,
    material: 'AC 32 dense base 40/60',
    orderedTons: 20.00,
    scheduled: _day(0, 8, 0),
    windowStart: _day(0, 7, 40),
    windowEnd: _day(0, 8, 20),
    distanceKm: 22.8,
    notes: 'Call the site foreman 15 minutes before arrival.',
  ),
  Delivery(
    number: '422215',
    orderNumber: '30771402',
    soldToName: 'Harlow & Sons Civil Engineering',
    soldToCode: '100318',
    shipToName: 'Ring Road Resurfacing',
    shipToAddress: 'Ring Road, Warwick',
    latitude: 52.282,
    longitude: -1.5849,
    siteContact: 'Priya Nair  •  +44 7700 900456',
    plantCode: 'QN2',
    shippingPoint: 'Quarry North - Plant 2',
    plantLatitude: _quarryNorthLat,
    plantLongitude: _quarryNorthLng,
    material: 'AC 20 close surface 100/150',
    orderedTons: 18.50,
    scheduled: _day(0, 8, 53),
    windowStart: _day(0, 8, 40),
    windowEnd: _day(0, 9, 15),
    distanceKm: 31.4,
  ),
  Delivery(
    number: '422214',
    orderNumber: '30771388',
    soldToName: 'Metro Paving Services',
    soldToCode: '100577',
    shipToName: 'Station Car Park',
    shipToAddress: 'Station Road, Rugby',
    latitude: 52.3785,
    longitude: -1.2503,
    siteContact: 'Tom Hale  •  +44 7700 900789',
    plantCode: 'QS1',
    shippingPoint: 'Quarry South - Plant 1',
    plantLatitude: _quarrySouthLat,
    plantLongitude: _quarrySouthLng,
    material: 'SMA 14 surface',
    orderedTons: 22.00,
    scheduled: _day(0, 9, 46),
    windowStart: _day(0, 9, 30),
    windowEnd: _day(0, 10, 10),
    distanceKm: 40.1,
    notes: 'Narrow access. Reverse in from the north entrance.',
  ),
];

// Completed deliveries
final List<Delivery> mockHistory = [
  Delivery(
    number: '421987',
    orderNumber: '30769950',
    soldToName: 'Northgate Construction Ltd',
    soldToCode: '100245',
    shipToName: 'Riverside Arena Works',
    shipToAddress: 'Arena Way, Coventry',
    latitude: 52.4486,
    longitude: -1.4955,
    siteContact: 'Dan Whitfield  •  +44 7700 900123',
    plantCode: 'QN2',
    shippingPoint: 'Quarry North - Plant 2',
    plantLatitude: _quarryNorthLat,
    plantLongitude: _quarryNorthLng,
    material: 'AC 32 dense base 40/60',
    orderedTons: 20.00,
    tareTons: 14.20,
    grossTons: 34.24,
    scheduled: _day(-1, 14, 10),
    windowStart: _day(-1, 13, 50),
    windowEnd: _day(-1, 14, 30),
    distanceKm: 22.8,
    status: DeliveryStatus.delivered,
  ),
  Delivery(
    number: '421950',
    orderNumber: '30769811',
    soldToName: 'Harlow & Sons Civil Engineering',
    soldToCode: '100318',
    shipToName: 'Ring Road Resurfacing',
    shipToAddress: 'Ring Road, Warwick',
    latitude: 52.282,
    longitude: -1.5849,
    siteContact: 'Priya Nair  •  +44 7700 900456',
    plantCode: 'QN2',
    shippingPoint: 'Quarry North - Plant 2',
    plantLatitude: _quarryNorthLat,
    plantLongitude: _quarryNorthLng,
    material: 'AC 20 close surface 100/150',
    orderedTons: 20.00,
    tareTons: 14.20,
    grossTons: 34.00,
    scheduled: _day(-1, 10, 30),
    windowStart: _day(-1, 10, 10),
    windowEnd: _day(-1, 10, 50),
    distanceKm: 31.4,
    status: DeliveryStatus.delivered,
  ),
];