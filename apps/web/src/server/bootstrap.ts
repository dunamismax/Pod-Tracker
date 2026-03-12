import { startObservability } from "@podwatch/observability";

let booted = false;

export const ensureServerBooted = () => {
  if (booted) {
    return;
  }

  const exporterUrl = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || undefined;

  startObservability({
    serviceName: process.env.OTEL_SERVICE_NAME || "podwatch-web",
    ...(exporterUrl ? { exporterUrl } : {}),
  });

  booted = true;
};
