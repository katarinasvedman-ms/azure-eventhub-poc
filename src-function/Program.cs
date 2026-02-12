using EventHubFunction.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        // Application Insights for distributed tracing
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        // SQL writer — singleton so the connection pool is shared across invocations.
        // SqlConnection pooling is handled by ADO.NET internally; we just need one service instance.
        services.AddSingleton<ISqlEventWriter>(sp =>
        {
            var config = context.Configuration;
            var connectionString = config["SqlConnectionString"]
                ?? throw new InvalidOperationException("SqlConnectionString app setting is required");
            var accessToken = config["SqlAccessToken"]; // Optional: pre-acquired AAD token
            var logger = sp.GetRequiredService<ILogger<SqlEventWriter>>();
            return new SqlEventWriter(connectionString, logger, accessToken);
        });
    })
    .ConfigureLogging(logging =>
    {
        // Reduce noise from Azure SDK internals
        logging.AddFilter("Azure.Messaging.EventHubs", LogLevel.Warning);
        logging.AddFilter("Azure.Core", LogLevel.Warning);
    })
    .Build();

host.Run();
