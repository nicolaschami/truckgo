// Compact labelled values with icons, and the delivery actions (call the
// site, navigate). Shared by the delivery flow and the delivery detail page.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../mock_deliveries.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);

// ---------------------------------------------------------------
// ACTIONS
// ---------------------------------------------------------------

/// Opens Google Maps with the route from the plant to the delivery site.
/// dir_action=navigate starts turn-by-turn right away when the driver is at
/// the plant; otherwise Google Maps shows the route preview.
Future<void> openNavigation(BuildContext context, Delivery d) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': '${d.plantLatitude},${d.plantLongitude}',
    'destination': '${d.latitude},${d.longitude}',
    'travelmode': 'driving',
    'dir_action': 'navigate',
  });
  await _launch(context, uri, 'Could not open Google Maps navigation',
      external: true);
}

/// Phone number from the site contact ("Name  •  +44 7700 900123").
// TODO: use a separate phone field once the API provides one.
String? sitePhone(Delivery d) {
  final match = RegExp(r'\+?[\d\s]{6,}').firstMatch(d.siteContact);
  final number = match?.group(0)?.replaceAll(' ', '');
  return number == null || number.isEmpty ? null : number;
}

Future<void> callSite(BuildContext context, Delivery d) async {
  final phone = sitePhone(d);
  if (phone == null) return;
  await _launch(context, Uri(scheme: 'tel', path: phone),
      'Could not start the call');
}

Future<void> _launch(
  BuildContext context,
  Uri uri,
  String error, {
  bool external = false,
}) async {
  var opened = false;
  try {
    opened = await launchUrl(
      uri,
      mode: external
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
    );
  }
}

// ---------------------------------------------------------------
// COMMON ROWS
// ---------------------------------------------------------------

/// Site contact, tappable to call when it has a phone number.
InfoItem siteContactItem(BuildContext context, Delivery d) => InfoItem(
      'Site contact',
      d.siteContact,
      Icons.person_outline,
      onTap: sitePhone(d) == null ? null : () => callSite(context, d),
      actionIcon: Icons.call,
    );

/// Customer site; with [navigate], tappable to open navigation.
InfoItem siteItem(BuildContext context, Delivery d, {bool navigate = false}) =>
    InfoItem(
      'Customer site',
      '${d.shipToName}\n${d.shipToAddress}',
      Icons.location_on_outlined,
      onTap: navigate ? () => openNavigation(context, d) : null,
      actionIcon: Icons.navigation_outlined,
    );

// ---------------------------------------------------------------
// WIDGETS
// ---------------------------------------------------------------

/// One labelled value with its icon. With [onTap], the value becomes a
/// button (e.g. call the site contact) shown by [actionIcon].
class InfoItem {
  const InfoItem(this.label, this.value, this.icon,
      {this.onTap, this.actionIcon});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final IconData? actionIcon;
}

/// Labelled values where each row can hold several values side by side
/// (equal columns), to keep related values on one line.
///
/// [card] = false draws only the rows, for use inside another card.
class FieldRows extends StatelessWidget {
  const FieldRows(this.rows, {super.key, this.card = true});

  final List<List<InfoItem>> rows;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Color(0x1A102A43)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < rows[i].length; j++) ...[
                  if (j > 0) const SizedBox(width: 12),
                  Expanded(child: FieldCell(rows[i][j])),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    if (!card) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
    );
  }
}

class FieldCell extends StatelessWidget {
  const FieldCell(this.item, {super.key});

  final InfoItem item;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(item.icon, size: 14, color: _grey),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                item.label,
                style: const TextStyle(fontSize: 11.5, color: _grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          item.value,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: _dark,
          ),
        ),
      ],
    );

    if (item.onTap == null) return text;

    // Tappable value: the whole cell reacts, with a round action button
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Expanded(child: text),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(item.actionIcon, size: 19, color: _blue),
          ),
        ],
      ),
    );
  }
}

/// A white card that shows only its title and [summary] until tapped.
class Collapsible extends StatefulWidget {
  const Collapsible({
    super.key,
    required this.title,
    required this.summary,
    required this.child,
  });

  final String title;
  final String summary; // shown while collapsed
  final Widget child;

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: _dark,
                          ),
                        ),
                        if (!_open) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.summary,
                            style: const TextStyle(fontSize: 12.5, color: _grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: _blue),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open
                ? Column(
                    children: [
                      const Divider(height: 1, color: Color(0x1A102A43)),
                      widget.child,
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
