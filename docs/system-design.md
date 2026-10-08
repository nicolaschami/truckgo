# TruckGo — System design

TruckGo is the driver app of a larger system. It is always connected to a
**dispatching system** in the office, which plans the deliveries and assigns
them to trucks.

The app talks to **our own neutral API**. A small integration layer on the
server translates that API to whichever dispatching system the customer uses
(SAP or any other), so the app does not change when the dispatching system
changes.

```
   ┌──────────────────────┐                      ┌──────────────────┐
   │  DISPATCHING SYSTEM  │ ── deliveries ──────▶│   TruckGo app    │
   │  (any vendor)        │ ── weights ─────────▶│   (driver phone) │
   │  orders, planning,   │                      │                  │
   │  truck assignment    │ ◀── statuses ────────│  GPS, geofences, │
   └──────────▲───────────┘ ◀── GPS positions ───│  delivery flow,  │
              │             ◀── proof of delivery│  signature       │
   ┌──────────┴───────────┐                      └──────────────────┘
   │  Plant weighbridge   │
   │  (1st & 2nd weight)  │
   └──────────────────────┘
```

## Key rules

- **Deliveries belong to the truck**, not the driver. After choosing a truck,
  the driver sees every delivery assigned to it, as soon as it is assigned.
- **Weights come from the dispatching system.** The app never records weights
  itself. To start, the app checks for new weights every few seconds while the
  truck is at the plant; this can later be replaced by push notifications
  without changing the screens.
- **Arrival at the customer site is always confirmed by the driver** with the
  "I have arrived" button. When the truck enters the ship-to geofence, the app
  only reminds the driver to confirm.
- **Arrival at the plant is automatic** when the truck enters the plant
  geofence.
- **Offline first:** everything the app sends is saved in SQLite first and sent
  when a connection is available.

## Delivery statuses

| # | Status          | Set by           | Trigger                                              |
|---|-----------------|------------------|------------------------------------------------------|
| 1 | Assigned        | Dispatching      | Delivery assigned to the truck                       |
| 2 | At plant        | App (automatic)  | Truck enters the plant geofence                      |
| 3 | Loading         | Dispatching      | 1st weight (tare) recorded                           |
| 4 | In transit      | Dispatching      | 2nd weight (gross) recorded; loaded = gross − tare   |
| 5 | Arrived at site | Driver           | Taps "I have arrived" (geofence only reminds)        |
| 6 | Unloading       | Driver           | Taps "Unload truck"                                  |
| 7 | Delivered       | Driver           | Customer signs (proof of delivery)                   |
| – | Cancelled       | Dispatching      | Any time before Delivered                            |

Every status change sent by the app includes the **time**, the **GPS
position** and the **trigger** (`geofence` or `driver`).

## Data exchanged with the dispatching system (draft)

| Direction    | What                                                        | When                          |
|--------------|-------------------------------------------------------------|-------------------------------|
| App → server | Login (alphanumeric username + numeric PIN)                 | Start of shift                |
| Server → app | Trucks and trailers                                         | Truck selection               |
| Server → app | Deliveries for the truck, including weights and status      | On open, then regular checks  |
| App → server | Status changes (status, time, GPS, trigger)                 | Each change                   |
| App → server | GPS positions, sent in batches                              | Every 30–60 s while tracking  |
| App → server | Proof of delivery: signature, customer name, notes, activities | At "Delivered"             |

## Local database (SQLite)

Schema in `lib/data/app_database.dart`. A delivery is identified everywhere
by **delivery number + plant code**. Dates are stored as UTC ISO-8601 text.

| Table                | Direction        | Purpose                                              |
|----------------------|------------------|------------------------------------------------------|
| session              | local            | Logged-in driver (one row)                           |
| driver_trucks        | local            | Remembered driver ↔ truck link, kept after logout   |
| vehicles             | from dispatching | Trucks and trailers                                  |
| plants               | from dispatching | Loading points; geofence radius (default 200 m)      |
| deliveries           | from dispatching | Deliveries per truck, weights, status; site geofence radius (default 200 m) |
| status_events        | to dispatching   | Every status change (time, GPS, trigger), `sent` flag |
| gps_positions        | to dispatching   | Tracking positions, `sent` flag                      |
| proof_of_delivery    | to dispatching   | Customer name, notes, signature (PNG in the database), `sent` flag |
| delivery_activities  | to dispatching   | Extra activities (chute, waiting time…)              |

**Retention:** on every start, finished deliveries older than 7 days are
removed together with their rows, **only when everything about them has been
sent**. Sent GPS positions older than 7 days are removed too. Unsent data is
never deleted.

**Driver ↔ truck:** the first truck chosen is remembered per driver. After
login the driver goes straight to that truck's deliveries and can tap the
truck badge to change it.

## Build order

1. Status model in the app (this table), with a test button that simulates
   weights arriving until the API exists.
2. Background tracking service (foreground service on Android, background
   location on iOS) — the reason the app asks for battery permission.
3. Plant geofence (automatic "At plant") and ship-to geofence (arrival
   reminder).
4. Weights driving the Loading and In transit statuses.
5. API client and SQLite storage with an offline send queue.

Status: steps 1 (status model), 2 (background tracking) and the SQLite part
of step 5 are done; the test deliveries are loaded into SQLite until the API
exists.

**Tracking rules** (`lib/tracking/tracking_service.dart`): GPS runs while a
truck's deliveries screen is open, also with the app in the background
(Android foreground service with a "Tracking your deliveries" notification,
iOS background location). One position is saved at most every 30 s in
`gps_positions`; every status change records the latest position if it is
less than 2 minutes old. If the driver swipes the app away, tracking stops
until the app is opened again.

**Geofence rules** (`lib/tracking/geofence_service.dart`), applied to the
truck's next delivery with the plant and site coordinates and radius from
the database:
- Plant zone entered while **Assigned** → status **At plant**
  (trigger `geofence`).
- Site zone entered while **In transit** → phone notification and an in-app
  "confirm arrival" dialog; only the driver's "Yes" sets **Arrived at site**.
  One reminder per visit: it repeats only after leaving beyond 1.5 × radius.
- GPS positions less precise than ±100 m are ignored.

## Open items

- Real plant coordinates (placeholders in `lib/mock_deliveries.dart`).
- OpenRouteService API key for truck routes on the in-app map
  (`flutter run --dart-define=ORS_API_KEY=...`).
- Keep or remove the Register button on the login page.
