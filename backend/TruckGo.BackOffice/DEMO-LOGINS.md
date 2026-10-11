# Demo logins (development only)

These accounts are created by the demo data (`TruckGo.Core/Data/SeedData.cs`)
when the local database is empty. They are **not secret** — the same values are
in the code. Never put real passwords (PostgreSQL, Supabase, clients) in this
file: it goes to GitHub.

## Back office — http://localhost:5100

Password for all: **`Demo-1234`**

| Email (login) | Role | Sees |
|---|---|---|
| `admin@demo.truckgo.local` | Admin | Everything, including Users and Settings |
| `dispatcher@demo.truckgo.local` | Dispatcher | All screens + Drivers |
| `viewer@demo.truckgo.local` | Viewer | All screens, changes nothing |
| `superadmin@truckgo.local` | SuperAdmin | TruckGo itself (no company yet) |

If you changed a demo password and forgot it: recreate the demo database
(see `../README.md`, "Master data") or ask an Admin to reset it on the Users screen.

## Driver app (API) — http://localhost:5000/scalar

| Username | PIN |
|---|---|
| `test1` | `1234` |
| `test2` | `5678` |

Demo truck `AB-1234` with trailer `TR-1001`.
