import 'package:flutter/material.dart';

import 'mock_deliveries.dart';
import 'widgets/delivery_info.dart';

const _blue = Color(0xFF0878E5);
const _grey = Color(0xFF58708C);
const _green = Color(0xFF2E9D5B);

/// Color of a status, shared by the list and the detail page.
Color deliveryStatusColor(DeliveryStatus status) => switch (status) {
      DeliveryStatus.assigned => _grey,
      DeliveryStatus.delivered => _green,
      DeliveryStatus.cancelled => const Color(0xFFD32F2F),
      _ => _blue, // in progress
    };

/// Small colored label (also used by the deliveries list)
class DeliveryStatusChip extends StatelessWidget {
  const DeliveryStatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class DeliveryDetailPage extends StatelessWidget {
  const DeliveryDetailPage({super.key, required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final completed = d.status.isFinished;

    final chipLabel = d.status.label;
    final chipColor = deliveryStatusColor(d.status);

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
              // TOP BAR
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        chipLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: chipColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // CONTENT
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    // Same grouping as the delivery flow screens.
                    // Navigation and calling only for open deliveries.
                    FieldRows([
                      [
                        InfoItem('Customer name', d.soldToName,
                            Icons.business_outlined),
                        InfoItem('Order number', d.orderNumber, Icons.tag),
                      ],
                      [siteItem(context, d, navigate: !completed)],
                      [
                        completed
                            ? InfoItem('Site contact', d.siteContact,
                                Icons.person_outline)
                            : siteContactItem(context, d),
                      ],
                      [
                        InfoItem('Shipping point', d.shippingPoint,
                            Icons.factory_outlined),
                        InfoItem('Material', d.material, Icons.layers_outlined),
                      ],
                      [
                        InfoItem('Planned',
                            '${fmtDay(d.scheduled)}, ${fmtTime(d.scheduled)}',
                            Icons.event_outlined),
                        InfoItem('Estimated',
                            '${fmtTime(d.windowStart)} - ${fmtTime(d.windowEnd)}',
                            Icons.schedule),
                      ],
                      [
                        InfoItem('Order quantity', fmtTons(d.orderedTons),
                            Icons.inventory_2_outlined),
                        InfoItem('Distance',
                            '${d.distanceKm.toStringAsFixed(1)} km',
                            Icons.route_outlined),
                      ],
                      [
                        InfoItem('Tare', fmtWeight(d.tareTons),
                            Icons.scale_outlined),
                        InfoItem('Gross', fmtWeight(d.grossTons),
                            Icons.scale_outlined),
                        InfoItem('Net', fmtWeight(d.loadedTons),
                            Icons.scale_outlined),
                      ],
                      if (d.notes != null)
                        [
                          InfoItem('Notes', d.notes!,
                              Icons.sticky_note_2_outlined),
                        ],
                    ]),

                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // BOTTOM BUTTON
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Back to deliveries',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
}
