# TruckGo — Back office design

Agreed screen by screen on 2026-10-09. This document is the reference for
building the back office: what each screen does, where its data comes from,
and what changes in the database and in the app. Nothing here is built yet.

Related: `system-design.md` (the driver app), `backend-plan.md` (API,
database, integration layer).

---

## 1. Principles

- **TruckGo is not a dispatching system and does not take orders.** It
  follows a delivery from the moment it is assigned to a truck until the
  customer signs.
- **There is no client yet.** We build a general system; when the first client
  needs a field we do not have, we add it (a database migration). Small
  client-specific details go in an **"extra info"** field (named values,
  shown automatically on the screens).
- **Master data always comes from the other system** (customers, ship-tos,
  plants, forwarding agents, trucks, trailers, deliveries, weights).
  TruckGo **never creates or edits** master data: no data-entry screens and
  no CSV/Excel import.
- **TruckGo owns only its own data:** back-office users, driver accounts,
  settings, and everything the app records (statuses, GPS positions, proof
  of delivery).
- **How master data arrives is not chosen yet** (an SQS queue or an API).
  Until then we **put it straight into the tables (seed data)**. The seed goes
  through the same "save customer / save ship-to / …" code that SQS or the
  API will use later, so adding the pipe later changes nothing else:

  ```
  seed data (now) ─┐
  SQS (later)     ─┼─▶  one "save" step per record type  ──▶  tables
  API (later)     ─┘
  ```

- **The code is commented generously**: what each class, field and endpoint
  means for the business, not only what it does.

### Who owns what

| Data | Owner | In the back office |
|---|---|---|
| Customers, ship-tos (always with GPS location) | Other system | View only |
| Plants | Other system | View only |
| Forwarding agents, trucks, trailers | Other system | View only |
| Deliveries, assigned truck + trailer, weights, cancellation | Other system | View; a Dispatcher may move a status forward with a reason |
| Status timeline, GPS positions, proof of delivery | TruckGo (app) | View |
| Driver accounts | TruckGo | Create / edit / reset PIN / unlock / deactivate |
| Back-office users and roles | TruckGo | Create / edit / reset password / unlock / deactivate |
| Settings | TruckGo | Admin edits |

---

## 2. Screens

Every list has a search box and an **"active only"** filter: when the other
system deactivates a record we keep it (old deliveries point to it) and mark
it inactive. **"Last received"** shows when the integration last sent the
record, to spot stale data.

### Screen 1 — Customers → ship-tos (view only)

- **Customer list:** code, name, city, number of ship-tos, last received.
- **Customer detail:** its fields, its ship-tos, and a map of all its
  ship-tos with their geofence circles.
- **Ship-to detail:** its fields, a map with the point and the geofence
  circle, its recent deliveries (links to screen 6), "Open in Google Maps".

Fields:
- **Customer (sold-to):** external code, name, address, city, postcode,
  country, phone, tax ID, active, last received, extra info.
- **Ship-to:** external code, customer, name, address, city, postcode,
  country, latitude, longitude, contact name, contact phone, delivery
  instructions, opening hours, active, last received, extra info.

### Screen 2 — Plants (view only)

- **List:** code, name, city, **trucks at the plant now**, **deliveries
  today**, and a map of all plants.
- **Detail:** fields, map with geofence circle, **"at the plant now"**
  (truck, delivery, at plant / loading, how long — the waiting time), and
  today's deliveries from this plant.

Fields: external code, name, address, city, postcode, country, latitude,
longitude, phone, active, last received, extra info.

### Screen 3 — Forwarding agents → trucks and trailers (view only)

- **Agent list:** code, name, city, trucks, trailers, busy now.
- **Agent detail:** fields; its trucks with **driver now, state, current
  delivery**; its trailers.
- **Truck detail:** fields, driver now, current delivery, today's
  deliveries, last known position on a map, link to the trace (screen 8).

Fields:
- **Forwarding agent:** external code, name, address, city, postcode,
  country, phone, email, tax ID, active, last received, extra info.
- **Truck / trailer:** plate, kind (truck or trailer), forwarding agent
  (**optional**), model, description, active, last received, extra info.

Decisions:
- The other system sends only **active / inactive**. The truck's **state**
  (idle / at plant / on the road / at ship-to) is **calculated by TruckGo**
  from the app's updates. No "maintenance" status.
- **No max load**: capacity belongs to the dispatching system.

### Screen 4 — Drivers (TruckGo's own data, editable)

- **List:** username, name, phone, truck now, last login, state (OK /
  locked / inactive).
- **Actions:** create; edit name and phone (the username never changes);
  **reset PIN**; **unlock** (after 5 wrong PINs); deactivate / reactivate —
  a driver is **never deleted** (deliveries and traces keep the name).
- **History:** recent logins (date, device) and recent deliveries.

Decisions:
- The **PIN is 4 digits, generated by TruckGo**, shown **once** on screen to
  pass to the driver, stored encrypted, never shown again.
- The driver **must change the PIN at first login** (and after a reset).
- **Any driver can pick any truck.**

Fields: username (unique), name, phone, PIN (hash), must change PIN, active,
failed PIN attempts, locked until, last login, last device, truck now.

### Screen 5 — Back-office users, roles and settings (TruckGo's own data)

- **Users:** login with **email + password**. Created with a **generated
  temporary password** shown once; must change it at first login. Reset
  password, unlock, deactivate — never deleted (history keeps who did what).
- **Roles:**

  | Role | Can do |
  |---|---|
  | Admin | Everything: users, drivers, settings, all screens |
  | Dispatcher | All screens; manages drivers (create, reset PIN, unlock); manual status with reason |
  | Viewer | All screens, changes nothing |

- **Several clients on one server:** a **TruckGo super-admin** creates a
  client company and its first Admin; each Admin manages their own users
  and drivers.
- **Limiting a Dispatcher to some plants:** later, when a client asks.
- **Settings** (Admin only), one set per client company — see section 3.

### Screen 6 — Deliveries (list and detail)

- **List:** filters date (default today), plant, status; search by delivery
  number, order, truck, customer. Columns: plant/number, order, customer,
  ship-to, truck, driver, window, net tonnes, status. **Refreshes by itself.**
  **Warnings** (section 4) shown on the row.
- **Detail:**
  1. Header: plant + number, order, status, customer, ship-to (links to
     screen 1), material, ordered tonnes, scheduled time, delivery window.
  2. Truck, **trailer**, driver.
  3. **Status timeline** with time and cause (dispatching system, plant
     geofence, 1st / 2nd weight, driver button, signature, or *manual by
     user + reason*).
  4. **Durations** from the timeline: waiting at plant, loading, travel,
     waiting at site, unloading, total.
  5. **Weights:** 1st, 2nd, net, ticket, weighbridge; re-weighs as history.
  6. **Proof of delivery:** signature, customer name, notes, driver notes —
     **downloadable as PDF**.
  7. Small map of the route, link to the full trace (screen 8).

Decisions:
- Quantities are **always in tonnes (TNE)**; no unit field.
- The **trailer comes from the dispatching system** with the delivery.
- A **Dispatcher can move a status forward manually with a mandatory
  reason** (example: the driver forgot to press Delivered). The timeline
  shows who did it and why. Never backwards, never after Delivered /
  Cancelled.

### Screen 7 — Live board

Four columns: **At plant** (at plant, loading) · **On the road** (in transit)
· **At ship-to** (arrived, unloading) · **Idle** (trucks with no delivery now).

Each card: truck, driver, delivery, destination, **time in this state**;
click → delivery detail. Cards with a warning turn orange/red and go to the
top of their column. Filter by plant. Refreshes by itself.

### Screen 8 — Map & trace

- **Live map:** active trucks at their last known position, coloured by
  state; plants and ship-tos with geofence circles; click a truck → its card.
- **Trace** of one delivery, or one truck for one day: the route on the map,
  **markers where each status changed**, **stops** (standing still longer
  than the setting, outside plant and ship-to), and a **replay slider**.

Later: **ETA** on the "on the road" cards (needs a routing service on the
server).

---

## 3. Settings (per client company, Admin edits)

| Setting | Default | Used by |
|---|---|---|
| Geofence radius — **one value for plants and ship-tos** | 200 m | App geofences, maps |
| Position send interval (app → server) | 60 s | App sync; how fresh the live board and map are |
| Long wait at plant | 30 min *(to confirm)* | Warning |
| Long wait at ship-to | 45 min *(to confirm)* | Warning |
| Arrival outside the delivery window — tolerance | 0 min *(to confirm)* | Warning |
| Long unexpected stop | 15 min *(to confirm)* | Trace stops + warning |
| GPS positions kept on the server | 12 months | Nightly clean-up |

The app reads the settings it needs (radius, send interval) from the server.
Statuses, weights and proofs of delivery are **kept for good**; only GPS
positions are deleted after the retention period.

## 4. Warnings

Calculated by TruckGo, shown on the delivery list (6), the live board (7)
and the map (8):

1. **Long wait at the plant** — at plant / loading longer than the setting.
2. **Long wait at the ship-to** — arrived / unloading longer than the setting.
3. **Arrival outside the delivery window.**
4. **Long unexpected stop** — standing still outside plant and ship-to
   longer than the setting.

---

## 5. Database changes (compared with today's `Data/Entities.cs`)

**Common to every master-data table:** `ExternalCode` (the code in the other
system; the "save" step updates the record with that code or creates it),
`IsActive`, `LastReceivedAt`, `Extra` (the extra-info named values, JSON).

| Table | Change |
|---|---|
| `customers` | **New** — screen 1 fields |
| `ship_tos` | **New** — screen 1 fields, belongs to a customer |
| `forwarding_agents` | **New** — screen 3 fields |
| `plants` | Add address, phone and the common fields; **remove `GeofenceRadiusM`** (now a setting) |
| `vehicles` | Add optional forwarding agent, description and the common fields; **remove `Status`** (state is calculated) |
| `deliveries` | **Point to `customer` and `ship_to`** instead of copying name, address, coordinates, radius, contact; add **`TrailerPlate`**; keep tonnes |
| `drivers` | Add phone, `MustChangePin`, last login, last device |
| `users` | **New** — back-office users: email, password hash, name, role, must change password, lock fields, active |
| `settings` | **New** — one row per company (section 3) |
| `status_events` | (planned in backend-plan) add **source** and, for manual changes, **user + reason** |
| `gps_positions`, `proofs_of_delivery` | As planned in backend-plan phase 2 |

## 6. Changes in the driver app

- **Change PIN screen** at first login and after a reset.
- **Trailer shown, not chosen**: it comes with the delivery.
- **Geofence radius and position send interval read from the server.**
- Positions sent to the server at the send interval (backend phase 2 sync
  worker).

## 7. Proposed build order

1. **Database changes + seed data** through the shared "save" step.
2. **Back-office skeleton** (Blazor, C#): login, users and roles, settings
   (screen 5).
3. **Master-data screens** 1, 2, 3 (view only — they work with seed data).
4. **Drivers** (screen 4) + the app's change-PIN screen.
5. **Backend phase 2**: the app sends statuses, positions and proof
   (needed for live data).
6. **Deliveries** (screen 6) with manual status and PDF.
7. **Live board** (7), **map & trace** (8), **warnings**.
