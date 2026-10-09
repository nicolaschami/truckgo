# TruckGo backend

C# / ASP.NET Core (.NET 10) + PostgreSQL. Plans: `../docs/backend-plan.md`
(API) and `../docs/back-office-design.md` (back office).

| Project | What |
|---|---|
| `TruckGo.Core` | Shared code: database (`Data/`), the master-data door (`Integration/`), users and settings (`Admin/`) |
| `TruckGo.Api` | The API used by the driver app (`/api/v1`) — http://localhost:5000 |
| `TruckGo.BackOffice` | The web back office (Blazor Server + MudBlazor) — http://localhost:5100 |
| `TruckGo.Api.Tests` | Tests on SQLite in memory (no PostgreSQL needed) |

## Commands (from the `backend` folder)

```
dotnet build                             # build everything
dotnet test                              # run the tests
dotnet run --project TruckGo.Api         # start the API (needs PostgreSQL)
dotnet run --project TruckGo.BackOffice  # start the back office (needs PostgreSQL)
dotnet ef migrations add <Name> --project TruckGo.Core --startup-project TruckGo.Api --output-dir Data/Migrations --namespace TruckGo.Data.Migrations
```

Stop a running API or back office with **Ctrl+C** in its terminal (a running
one blocks the next build).

API: open **http://localhost:5000/scalar** to see and try every endpoint. The
generated contract is at `/openapi/v1.json`.

Back office: open **http://localhost:5100** and log in.

## Demo logins

- Drivers (app): `test1` / PIN `1234`, `test2` / PIN `5678`; demo truck
  `AB-1234` with trailer `TR-1001`.
- Back office, password `Demo-1234` for all:
  `admin@demo.truckgo.local` (Admin), `dispatcher@demo.truckgo.local`
  (Dispatcher), `viewer@demo.truckgo.local` (Viewer),
  `superadmin@truckgo.local` (TruckGo SuperAdmin, no company).

## Master data

Customers, ship-tos, plants, forwarding agents, vehicles and deliveries come
from the client's other system and enter **only** through
`TruckGo.Core/Integration/MasterDataImport.cs` (one "save" method per record
type). Today the seed data (`TruckGo.Core/Data/SeedData.cs`) uses it; an SQS
queue or an API will use the same methods later.

The demo data is loaded into an **empty** database when the API or the back
office starts. After a model change during development, recreate it:

```
$env:ASPNETCORE_ENVIRONMENT='Development'
dotnet ef database drop --force --project TruckGo.Core --startup-project TruckGo.Api
dotnet run --project TruckGo.Api     # migrates and seeds again
```

## Database password

Never in `appsettings*.json`. Stored once with user secrets, shared by the API
and the back office (same `UserSecretsId`):

```
dotnet user-secrets set "ConnectionStrings:TruckGo" "Host=localhost;Port=5432;Database=truckgo;Username=postgres;Password=<yours>" --project TruckGo.Api
```
