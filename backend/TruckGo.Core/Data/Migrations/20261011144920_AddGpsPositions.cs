using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TruckGo.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddGpsPositions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Positions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    ClientId = table.Column<Guid>(type: "uuid", nullable: false),
                    TruckPlate = table.Column<string>(type: "text", nullable: false),
                    DeliveryId = table.Column<Guid>(type: "uuid", nullable: true),
                    DriverId = table.Column<Guid>(type: "uuid", nullable: true),
                    Latitude = table.Column<double>(type: "double precision", nullable: false),
                    Longitude = table.Column<double>(type: "double precision", nullable: false),
                    AccuracyM = table.Column<double>(type: "double precision", nullable: true),
                    SpeedKmh = table.Column<double>(type: "double precision", nullable: true),
                    Heading = table.Column<double>(type: "double precision", nullable: true),
                    RecordedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ReceivedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Positions", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Positions_ClientId",
                table: "Positions",
                column: "ClientId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Positions_CompanyId_TruckPlate_RecordedAt",
                table: "Positions",
                columns: new[] { "CompanyId", "TruckPlate", "RecordedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_Positions_DeliveryId",
                table: "Positions",
                column: "DeliveryId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Positions");
        }
    }
}
