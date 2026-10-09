# TruckGo backend

C# / ASP.NET Core (.NET 10) + PostgreSQL. Plan: `../docs/backend-plan.md`.

| Project | What |
|---|---|
| `TruckGo.Api` | The API used by the driver app (`/api/v1`) |
| `TruckGo.Api.Tests` | Tests: the whole API in memory on SQLite (no PostgreSQL needed) |

## Commands (from the `backend` folder)

```
dotnet build                      # build
dotnet test                       # run the tests
dotnet run --project TruckGo.Api  # start the API (needs PostgreSQL)
dotnet ef migrations add <Name> --project TruckGo.Api --output-dir Data/Migrations
```

Once running (Development), open **http://localhost:5000/scalar** to see and
try every endpoint. The generated contract is at `/openapi/v1.json`.

Demo drivers: `test1` / PIN `1234`, `test2` / PIN `5678`; demo truck `AB-1234`
with trailer `TR-1001`.

Demo back-office users (for the back office, step 2): `superadmin@truckgo.local`,
`admin@demo.truckgo.local`, `dispatcher@demo.truckgo.local`,
`viewer@demo.truckgo.local` — password `Demo-1234`.

## Master data

Customers, ship-tos, plants, forwarding agents, vehicles and deliveries come
from the client's other system and enter **only** through
`Integration/MasterDataImport.cs` (one "save" method per record type). Today
the seed data (`Data/SeedData.cs`) uses it; an SQS queue or an API will use
the same methods later. Design: `../docs/back-office-design.md`.

The demo data is loaded into an **empty** database at start-up. After a
model change during development, recreate it:

```
$env:ASPNETCORE_ENVIRONMENT='Development'
dotnet ef database drop --force --project TruckGo.Api
dotnet run --project TruckGo.Api     # migrates and seeds again
```

## Database password

Never in `appsettings*.json`. Store it once with user secrets:

```
dotnet user-secrets init --project TruckGo.Api
dotnet user-secrets set "ConnectionStrings:TruckGo" "Host=localhost;Port=5432;Database=truckgo;Username=postgres;Password=<yours>" --project TruckGo.Api
```
