#:package Microsoft.Extensions.Configuration.Binder@10.0.9
#:package Microsoft.Extensions.DependencyInjection@10.0.9
#:package Microsoft.Extensions.Logging.Abstractions@10.0.9
#:package OpenTelemetry.Exporter.Console@1.16.0
#:package OpenTelemetry.Exporter.OpenTelemetryProtocol@1.16.0
#:package OpenTelemetry.Extensions.Hosting@1.16.0

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System.Diagnostics;
using System.Diagnostics.Metrics;

var services = new ServiceCollection();

var resourceBuilder = ResourceBuilder.CreateDefault();

services.AddLogging(builder =>
    builder.AddOpenTelemetry(options =>
    {
        options.SetResourceBuilder(resourceBuilder);
        options.IncludeFormattedMessage = true;
        options.IncludeScopes = true;
        options.ParseStateValues = true;
        options.AddConsoleExporter();
        options.AddOtlpExporter();
    }));

services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(resourceBuilder)
        .SetSampler(new AlwaysOnSampler())
        .AddSource("OtlpTest")
        .AddConsoleExporter()
        .AddOtlpExporter())
    .WithMetrics(metrics => metrics
        .SetResourceBuilder(resourceBuilder)
        .AddMeter("OtlpTest.Metrics")
        .AddConsoleExporter()
        .AddOtlpExporter((_, options) => options.TemporalityPreference = MetricReaderTemporalityPreference.Delta));

using var provider = services.BuildServiceProvider();

var logger = provider.GetRequiredService<ILogger<Program>>();
var tracerProvider = provider.GetRequiredService<TracerProvider>();
var meterProvider = provider.GetRequiredService<MeterProvider>();

using var activitySource = new ActivitySource("OtlpTest");
using var meter = new Meter("OtlpTest.Metrics");
var requestCounter = meter.CreateCounter<long>("demo.requests");

logger.LogInformation("{Message}", "Hello, OpenTelemetry!");

using (var activity = activitySource.StartActivity("demo-operation"))
{
    activity?.SetTag("demo.tag", "otlp-test");
    requestCounter.Add(1, new KeyValuePair<string, object?>("endpoint", "demo"));
    logger.LogInformation("Generated one span + one metric + one log.");
}

tracerProvider.ForceFlush();
meterProvider.ForceFlush();

/* Makefile
export OTEL_SERVICE_NAME=poc-app
export OTEL_RESOURCE_ATTRIBUTES=service.instance.id=instance-local-01,service.version=1.2.3

run:
	dotnet run otlp-test.cs
*/
