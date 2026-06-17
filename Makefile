export OTEL_SERVICE_NAME=poc-app
export OTEL_RESOURCE_ATTRIBUTES=service.instance.id=instance-local-01,service.version=1.2.3,deployment.environment=staging

run:
	dotnet run otlp-test.cs
