using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TruckGo.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddCustomerSalesRep : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SalesRep",
                table: "Customers",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SalesRep",
                table: "Customers");
        }
    }
}
