using Azure.Identity;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using Azure.Messaging.EventHubs.Processor;
using Azure.Storage.Blobs;
using LogsysNgPoC.Configuration;
using LogsysNgPoC.Services;

var builder = WebApplication.CreateBuilder(args);

// ========================
// Configuration Setup
// ========================
var eventHubOptions = new EventHubOptions();
builder.Configuration.GetSection("EventHub").Bind(eventHubOptions);

var apiOptions = new ApiOptions();
builder.Configuration.GetSection("Api").Bind(apiOptions);

builder.Services.Configure<EventHubOptions>(builder.Configuration.GetSection("EventHub"));
builder.Services.Configure<ApiOptions>(builder.Configuration.GetSection("Api"));

// ========================
// Azure Client Setup
// ========================
var credential = new DefaultAzureCredential();

// Event Hub Producer Client
var producerClient = new EventHubProducerClient(
    eventHubOptions.FullyQualifiedNamespace,
    eventHubOptions.HubName,
    credential);

builder.Services.AddSingleton(producerClient);

// ========================
// Application Services
// ========================
builder.Services.AddSingleton<IEventHubProducerService, EventHubProducerService>();
builder.Services.AddSingleton<IEventHubConsumerService, EventHubConsumerService>();
builder.Services.AddSingleton<IEventBatchingService, EventBatchingService>();

// ========================
// Observability
// ========================
builder.Services
    .AddApplicationInsightsTelemetry()
    .AddLogging(logging =>
    {
        logging.AddApplicationInsights();
        logging.AddConsole();
    });

// ========================
// API Setup
// ========================
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "LogsysNG Event Hub PoC",
        Version = "v1",
        Description = "Proof of Concept for high-throughput Event Hub integration"
    });
});

builder.Services.AddHealthChecks();
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});

var app = builder.Build();

// ========================
// Middleware Pipeline
// ========================
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors("AllowAll");
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

// ========================
// Event Hub Consumer Startup
// ========================
var consumerService = app.Services.GetRequiredService<IEventHubConsumerService>();
var batchingService = app.Services.GetRequiredService<IEventBatchingService>();
var producerService = app.Services.GetRequiredService<IEventHubProducerService>();

// Start consumer in background
_ = consumerService.StartProcessingAsync();

// Subscribe to batch ready events
var eventBatchingServiceTyped = batchingService as EventBatchingService;
if (eventBatchingServiceTyped != null)
{
    eventBatchingServiceTyped.BatchReady += async (sender, args) =>
    {
        try
        {
            var publishedCount = await producerService.PublishEventBatchAsync(args.Events);
            if (publishedCount > 0)
            {
                app.Logger.LogInformation("Published batch of {Count} events", publishedCount);
            }
        }
        catch (Exception ex)
        {
            app.Logger.LogError(ex, "Failed to publish batch");
        }
    };
}

// Graceful shutdown
app.Lifetime.ApplicationStopping.Register(async () =>
{
    app.Logger.LogInformation("Application shutting down...");
    await consumerService.StopProcessingAsync();
});

app.Run();

static string GetStorageAccountName(string connectionString)
{
    var parts = connectionString.Split(';');
    foreach (var part in parts)
    {
        if (part.StartsWith("AccountName="))
            return part["AccountName=".Length..];
    }
    throw new InvalidOperationException("Could not extract storage account name from connection string");
}
