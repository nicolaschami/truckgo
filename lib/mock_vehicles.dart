// Mock data for the truck / trailer selection screen.
// Later, replace these lists with data coming from your server.

enum VehicleStatus { available, inUse, maintenance }

extension VehicleStatusLabel on VehicleStatus {
  String get label => switch (this) {
        VehicleStatus.available => 'Available',
        VehicleStatus.inUse => 'In use',
        VehicleStatus.maintenance => 'Maintenance',
      };
}

class Vehicle {
  const Vehicle({
    required this.plate,
    required this.model,
    required this.detail,
    required this.isTruck,
    this.status = VehicleStatus.available,
  });

  final String plate; // registration number
  final String model; // Volvo FH16, Curtainsider...
  final String detail; // 6x4 tractor, 34 pallets...
  final bool isTruck;
  final VehicleStatus status;

  bool get isAvailable => status == VehicleStatus.available;
}

const List<Vehicle> mockTrucks = [
  Vehicle(
    plate: 'AB-1234',
    model: 'Volvo FH16',
    detail: 'Tractor unit 6x4',
    isTruck: true,
  ),
  Vehicle(
    plate: 'TG-5821',
    model: 'Scania R500',
    detail: 'Tractor unit 4x2',
    isTruck: true,
  ),
  Vehicle(
    plate: 'MN-7740',
    model: 'Mercedes Actros',
    detail: 'Tractor unit 4x2',
    isTruck: true,
    status: VehicleStatus.inUse,
  ),
  Vehicle(
    plate: 'RT-3092',
    model: 'DAF XF 480',
    detail: 'Tractor unit 6x2',
    isTruck: true,
  ),
  Vehicle(
    plate: 'KL-1188',
    model: 'MAN TGX',
    detail: 'Tractor unit 4x2',
    isTruck: true,
    status: VehicleStatus.maintenance,
  ),
  Vehicle(
    plate: 'ZX-9054',
    model: 'Iveco S-Way',
    detail: 'Tractor unit 4x2',
    isTruck: true,
  ),
  Vehicle(
    plate: 'PL-4417',
    model: 'Renault T High',
    detail: 'Tractor unit 4x2',
    isTruck: true,
    status: VehicleStatus.inUse,
  ),
  Vehicle(
    plate: 'BC-2260',
    model: 'Volvo FM',
    detail: 'Rigid 8x4',
    isTruck: true,
  ),
];

const List<Vehicle> mockTrailers = [
  Vehicle(
    plate: 'TR-1001',
    model: 'Curtainsider',
    detail: '34 pallets',
    isTruck: false,
  ),
  Vehicle(
    plate: 'TR-1002',
    model: 'Refrigerated',
    detail: '33 pallets, -25 C',
    isTruck: false,
  ),
  Vehicle(
    plate: 'TR-1003',
    model: 'Flatbed',
    detail: '27 t payload',
    isTruck: false,
    status: VehicleStatus.inUse,
  ),
  Vehicle(
    plate: 'TR-1004',
    model: 'Tanker',
    detail: '30,000 L',
    isTruck: false,
  ),
  Vehicle(
    plate: 'TR-1005',
    model: 'Container chassis',
    detail: '40 ft',
    isTruck: false,
  ),
  Vehicle(
    plate: 'TR-1006',
    model: 'Box trailer',
    detail: '90 m3',
    isTruck: false,
    status: VehicleStatus.maintenance,
  ),
];