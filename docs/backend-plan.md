# TruckGo — Backend plan

The driver app is complete on its own (see `system-design.md`). This plan
covers what sits behind it: **the TruckGo API**, **the TruckGo database**,
and **the integration layer** that connects to the customer's dispatching
system.

```
 ┌────────────┐  HTTPS/JSON  ┌──────────────────────────────┐        ┌───────────────────┐
 │ TruckGo    │ ───────────▶ │ 1. TruckGo API  (/api/v1)    │        │ Dispatching system│
 │ driver app │ ◀─────────── │    auth, deliveries, events, │        │ (any vendor: SAP, │
 │ (SQLite)   │              │    positions, proof of deliv.│        │  TMS, ERP, …)     │
 └────────────┘              ├──────────────────────────────┤        └─────────▲─────────┘
                             │ 2. TruckGo database          │                  │
                             │    (our own, vendor-neutral) │                  │
                             ├──────────────────────────────┤  adapter per     │
                             │ 3. Integration layer         │ ◀── vendor ─────▶│
                             │    inbound queue + outbox    │                  │
                             └──────────────────────────────┘  Weighbridge ────┘
```

**The rule that keeps it clean:** the app and the TruckGo database only know
TruckGo concepts (delivery, plant, site, weighing, status). Everything that is
specific to one dispatching system lives in its **adapter** in the
integration layer. A new customer with a different system = a new adapter,
nothing else changes.

---

## 1. The TruckGo API (what the app calls)

REST + JSON over HTTPS, versioned under `/api/v1`. All times in UTC ISO-8601.
A delivery is identified by **plant code + delivery number**, as in the app.

### Authentication
| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/login` | `{username, pin, deviceId}` → access token (short, ~1 h) + refresh token |
| POST | `/auth/refresh` | new access token, so the driver is not logged out mid-shift |
| POST | `/auth/logout` | revoke the refresh token |

PINs are stored hashed (never in clear). Too many wrong PINs lock the account
for a few minutes.

### Reading (server → app)
| Method | Path | Purpose |
|---|---|---|
| GET | `/vehicles` | trucks and trailers (with status) for truck selection |
| PUT | `/drivers/me/truck` | `{truckPlate, trailerPlates[]}` — the driver ↔ truck link; also told to dispatching |
| GET | `/trucks/{plate}/deliveries?since=` | the truck's deliveries, **including plant + site coordinates and radius, status, 1st and 2nd weights**. `since` returns only what changed (cheap to call often) |
| GET | `/deliveries/{plant}/{number}` | one delivery — used every few seconds at the weighbridge to get the **1st / 2nd weight** |

The weights are fields of the delivery (`tareTons`, `grossTons`, their
timestamps and the weighbridge ticket number), so "get first weight" and "get
second weight" are the same call: the app sees them appear and moves to
*Loading* / *In transit*, exactly as the test buttons do today.

### Writing (app → server) — offline-safe
| Method | Path | Purpose |
|---|---|---|
| POST | `/events` | batch of status changes `{clientId, plant, number, status, trigger, time, lat, lng}` |
| POST | `/positions` | batch of GPS positions `{clientId, truck, lat, lng, accuracy, speed, heading, time}` |
| POST | `/deliveries/{plant}/{number}/proof` | proof of delivery: customer name, notes, driver notes, activities + **signature PNG** (multipart) |

**Idempotency (important for offline):** every row the app sends carries a
`clientId` (a UUID made on the phone). If the same batch is sent twice — weak
signal, the reply got lost — the server recognises the ids and stores nothing
twice. The app marks rows `sent = 1` only after the server's OK.

**The server re-checks every status change** with the same rules as the app
(only forward, nothing after Delivered/Cancelled), so a buggy or old app can
never corrupt a delivery.

### Later
- **Push notifications** (Firebase) for "new delivery", "weight arrived",
  "cancelled" — replaces part of the polling; the endpoints stay the same.
- `POST /devices` to register the push token.

---

## 2. The TruckGo database (server)

Our own database, the same concepts as the app's SQLite plus what the server
needs. Proposed engine: **PostgreSQL** (free, robust, good with time-series
GPS data; PostGIS available if we ever need geo queries).

| Table | Content |
|---|---|
| `companies` | the customer companies using TruckGo (one per dispatching system connection) |
| `drivers` | username, PIN hash, company, active |
| `vehicles` | trucks and trailers (plate, type, model, status) |
| `driver_truck_links` | current and past driver ↔ truck links (who drove what, when) |
| `plants` | code, name, latitude, longitude, geofence radius |
| `customers` / `sites` | sold-to and ship-to, site coordinates, radius, contact, phone |
| `deliveries` | number + plant (key), order, truck, material, ordered tons, schedule, **status**, `updated_at` |
| `weighings` | 1st and 2nd weight per delivery, time, ticket number, weighbridge — kept as history (a re-weigh adds a row) |
| `status_events` | every status change: who/what triggered it, device time, server time, GPS |
| `gps_positions` | the truck trails — the biggest table, split by month, old months archived |
| `proofs_of_delivery` | names, notes, signature (stored as a file in object storage, path in the row) |
| `delivery_activities` | chute, waiting time, extra km… |
| `devices` | phone id, app version, push token, last seen |
| `integration_inbox` | every message received from the dispatching system (raw + processed status) |
| `integration_outbox` | every message to send to the dispatching system (pending / sent / failed, retries) |
| `external_ids` | mapping between TruckGo ids and the dispatching system's ids |
| `audit_log` | logins, admin changes |

Retention (proposal): GPS positions **12 months** online, everything about
deliveries **as long as the law requires** for delivery notes (usually years).
The phone keeps only 7 days, as today.

---

## 3. The integration layer (dispatching system ⇄ TruckGo)

Two directions, both through a queue so neither side has to be online at the
same moment.

**Inbound — dispatching → TruckGo** (deliveries, assignments, weights,
cancellations). Two ways an adapter can deliver them, depending on what the
dispatching system can do:
1. **It calls us:** a small integration API —
   `PUT /integration/v1/deliveries` (create/update),
   `POST /integration/v1/weighings` (1st/2nd weight),
   `POST /integration/v1/deliveries/{plant}/{number}/cancel`,
   protected by an API key per company.
2. **We fetch from it:** the adapter polls the dispatching system (REST,
   database view, files, SAP IDoc/BAPI…) every few seconds/minutes.

Everything received lands in `integration_inbox` first, then is applied to
the TruckGo tables — so a bad message can be inspected and replayed.

**Outbound — TruckGo → dispatching** (statuses, proof of delivery, positions,
driver ↔ truck link). Every change writes a row in `integration_outbox`
(*outbox pattern*); a worker sends them with retries until the dispatching
system confirms. A dispatching system that is down for an hour loses nothing.

**Adapters:** one per dispatching system, each only translating between the
vendor's format and ours. The first one we build is a **simulator** —
a small web page "Fake dispatch" that creates deliveries, assigns them to a
truck and sends 1st/2nd weights. It replaces the app's orange test tools and
lets us test everything end to end before any real customer system exists.

---

## 4. Build phases

| Phase | Content | Result |
|---|---|---|
| **0. Contract** | The API written as an **OpenAPI** file (every endpoint, field, error) + the decisions below | Both sides build against the same contract |
| **1. Read** | API project, database, login, vehicles, deliveries (`GET`), test data loaded server-side | The app shows deliveries **from the server** instead of mock data |
| **2. Write + sync** | `POST` events / positions / proof; in the app: a sync worker that sends the `sent = 0` rows, retries, and polls weights at the plant | Data leaves the phone; office can see it |
| **3. Fake dispatch** | Integration inbox/outbox + the simulator page | Full loop without a real dispatching system; app test tools no longer needed |
| **4. First real adapter** | Connector to the first customer's dispatching system | Real deliveries and weights |
| **5. Production** | Hosting, HTTPS, backups, monitoring, push notifications, office map of trucks | Ready for drivers |

Changes needed in the app (phase 2): a `client_id` (UUID) column on the
tables it sends, the API client, a sync worker, and a database version 2
migration so testers keep their data.

---

## 5. Decisions (2026-10-08)

| # | Decision | Chosen |
|---|---|---|
| 1 | Backend language/framework | **C# / ASP.NET Core** |
| 2 | Database | **PostgreSQL** (free, open source) |
| 3 | One company or many? | **Many**: a `company` on every row from the start |
| 4 | Hosting | **Local development first**; hosting decided later |
| 5 | First dispatching system | **Not known yet**: start with the **Fake dispatch** simulator |
| 6 | Where do weights come from? | A **simulated weighbridge** (realistic random 1st/2nd weights) inside Fake dispatch, until a real one is connected |
