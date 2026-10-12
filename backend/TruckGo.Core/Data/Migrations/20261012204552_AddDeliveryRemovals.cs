using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TruckGo.Core.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddDeliveryRemovals : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "DeliveryRemovals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    TruckPlate = table.Column<string>(type: "text", nullable: false),
                    DeliveryId = table.Column<Guid>(type: "uuid", nullable: false),
                    RemovedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DeliveryRemovals", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DeliveryRemovals_Deliveries_DeliveryId",
                        column: x => x.DeliveryId,
                        principalTable: "Deliveries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_DeliveryRemovals_CompanyId_TruckPlate_RemovedAt",
                table: "DeliveryRemovals",
                columns: new[] { "CompanyId", "TruckPlate", "RemovedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_DeliveryRemovals_DeliveryId",
                table: "DeliveryRemovals",
                column: "DeliveryId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DeliveryRemovals");
        }
    }
}
