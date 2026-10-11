# How to add a field — what we learned with `SalesRep`

On 11 October 2026 we added **SalesRep** (the sales representative of a
customer) from the database all the way to the Customers screen. This page
keeps the road and the lessons, so the next field is quick.

---

## The road, in order

A value travels from the database to the screen through these files. Adding a
field means visiting each one, **in this order**.

| # | Where | What we added for `SalesRep` | Why |
|---|---|---|---|
| 1 | `TruckGo.Core/Data/Entities.cs` — class `Customer` | `public string? SalesRep { get; set; }` + a `/// <summary>` comment | The **entity**: the C# form of one table row. Each property = one column. `?` = may be empty. |
| 2a | `TruckGo.Core/Integration/MasterDataMessages.cs` — `CustomerMessage` | `string? SalesRep = null,` | The **message**: what the other system can send us. |
| 2b | `TruckGo.Core/Integration/MasterDataImport.cs` — `SaveCustomerAsync` | `row.SalesRep = m.SalesRep;` | The **door**: copies the received value into the row and saves it. |
| 3 | `TruckGo.Core/Data/SeedData.cs` | `SalesRep: "Laura Bennett"` on the demo customers | **Demo data**, so there is something to see. |
| 4 | **Migration** (a command, see below) | file `…_AddCustomerSalesRep.cs` | Creates the **column in PostgreSQL**. |
| 5 | `TruckGo.Core/Queries/CustomerQueries.cs` | `string? SalesRep` in the records `CustomerRow` / `CustomerDetail`, and `c.SalesRep` where they are filled | The **package**: what the screen receives. |
| 6 | `TruckGo.BackOffice/Components/Pages/Customers/Customers.razor` (and/or `CustomerPage.razor`) | a header `<MudTh>Sales rep</MudTh>` + a cell `@(context.SalesRep ?? "—")` | The **screen**: writes the value into the HTML. |
| 7 | Terminal | `dotnet build`, `dotnet test`, start the back office, open the page | **Check** it works. |

---

## The migration (step 4) has TWO parts

From the `backend` folder, with the API and the back office **stopped**
(Ctrl+C in their terminals):

**a) Create** the migration file — the database is not touched yet:
```
dotnet ef migrations add AddCustomerSalesRep --project TruckGo.Core --startup-project TruckGo.Api --output-dir Data/Migrations --namespace TruckGo.Data.Migrations
```
Open the new file in `TruckGo.Core/Data/Migrations/` and check it only says
`AddColumn` for your field.

**b) Apply** it — this creates the column in PostgreSQL:
```
dotnet ef database update --project TruckGo.Core --startup-project TruckGo.Api
```
(Starting the API or the back office in development also applies it.)

Type each command **on one line, complete** — starting with `dotnet ef`.
`database update` alone is not a command.

---

## The lessons (the things that went wrong, and why)

1. **Never add a column by hand** (pgAdmin, SQL `ALTER TABLE`).
   EF Core keeps its own record of the tables (the migrations). A column added
   by hand is unknown to it: the next migration tries to add it again and
   fails, and other computers never get it. Change the C# entity, then let a
   migration change the database.
   *Changing **data** by hand (`UPDATE`) is fine; changing the **structure** is not.*

2. **C# is case-sensitive.** `salesrep`, `Salesrep` and `SalesRep` are three
   different names. Use **PascalCase** (`SalesRep`, `TaxId`, `LastReceivedAt`)
   everywhere, and the **same spelling** in the entity, the record and the page.
   To rename everywhere at once: cursor on the name, **F2**, new name, Enter.

3. **PostgreSQL needs double quotes for names with capitals.**
   Without quotes PostgreSQL turns a name into lower case:
   ```sql
   UPDATE public."Customers" SET SalesRep = 'N/A';      -- ERROR: column "salesrep" does not exist
   UPDATE public."Customers" SET "SalesRep" = 'N/A';    -- OK
   ```
   **Double quotes `" "` for names** (tables, columns) — **single quotes `' '`
   for values** (text). (SQL Server ignores case and uses `[ ]`; PostgreSQL does not.)

4. **Empty is better than "N/A".** Leave "no value" as NULL; the screens show
   it as "—", and searches are not fooled by fake values.

5. **The demo data only runs on an empty database.** After adding a field,
   existing rows have it empty. To see the demo values, recreate the demo
   database (`../README.md`, "Master data"), or fill them with an `UPDATE`.

6. **Save before checking.** A ● on a file's tab in VS Code = not saved.
   **File → Save All** saves every open file.

7. **Read the build error — it says exactly what is missing.**
   *"CustomerMessage does not contain a definition for SalesRep"* = step 2a was
   not done yet.

---

## Quick checklist for the next field

- [ ] 1 Entity (PascalCase, `?` if it may be empty, comment)
- [ ] 2 Message + door (if it comes from the other system)
- [ ] 3 Demo data
- [ ] 4a `dotnet ef migrations add <Name> …` → check the file
- [ ] 4b `dotnet ef database update …`
- [ ] 5 Record(s) in the queries
- [ ] 6 Page
- [ ] 7 Build, test, look at the screen
