using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using Scalar.AspNetCore;
using TruckGo.Api.Auth;
using TruckGo.Api.Data;
using TruckGo.Api.Deliveries;

var builder = WebApplication.CreateBuilder(args);

// DATABASE (PostgreSQL)
builder.Services.AddDbContext<TruckGoDb>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("TruckGo")));

// LOGIN TOKENS (JWT)
builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection("Jwt"))
    .Validate(o => o.SigningKey.Length >= 32, "Jwt:SigningKey must be at least 32 characters")
    .ValidateOnStart();
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<Microsoft.Extensions.Options.IOptions<JwtOptions>>((bearer, jwt) =>
    {
        bearer.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = jwt.Value.Issuer,
            ValidAudience = jwt.Value.Audience,
            IssuerSigningKey = jwt.Value.Key(),
            ClockSkew = TimeSpan.FromMinutes(1),
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddProblemDetails();

// JSON: enums as the app writes them ("inTransit"), no nulls dropped
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));

// OPENAPI: the contract, generated from the code, with the login token
builder.Services.AddOpenApi(o => o.AddDocumentTransformer((doc, _, _) =>
{
    doc.Info = new OpenApiInfo
    {
        Title = "TruckGo API",
        Version = "v1",
        Description = "API used by the TruckGo driver app. See docs/backend-plan.md.",
    };
    doc.Components ??= new OpenApiComponents();
    doc.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
    doc.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "Token from POST /api/v1/auth/login",
    };
    return Task.CompletedTask;
}));

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseAuthentication();
app.UseAuthorization();

// Development: the contract and a test page at /scalar
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference(o => o
        .WithTitle("TruckGo API")
        .AddPreferredSecuritySchemes("Bearer"));
}

var api = app.MapGroup("/api/v1");
api.MapAuthEndpoints();
api.MapDeliveryEndpoints();

app.MapGet("/", () => Results.Redirect("/scalar")).ExcludeFromDescription();

// Development: create/upgrade the database and load the demo data
if (app.Environment.IsDevelopment() && app.Configuration.GetValue<bool>("Database:MigrateAndSeed"))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<TruckGoDb>();
    await db.Database.MigrateAsync();
    await SeedData.EnsureSeededAsync(db);
}

app.Run();

// Lets the tests start the API in memory
public partial class Program;
