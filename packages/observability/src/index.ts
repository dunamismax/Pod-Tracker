import {
  DiagConsoleLogger,
  DiagLogLevel,
  diag,
  SpanStatusCode,
  trace,
} from "@opentelemetry/api";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { resourceFromAttributes } from "@opentelemetry/resources";
import {
  BasicTracerProvider,
  BatchSpanProcessor,
  ConsoleSpanExporter,
} from "@opentelemetry/sdk-trace-base";
import { ATTR_SERVICE_NAME } from "@opentelemetry/semantic-conventions";

let started = false;

export const startObservability = ({
  serviceName,
  exporterUrl,
}: {
  serviceName: string;
  exporterUrl?: string;
}) => {
  if (started) {
    return;
  }

  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.ERROR);

  const exporter = exporterUrl
    ? new OTLPTraceExporter({
        url: exporterUrl,
      })
    : new ConsoleSpanExporter();

  const provider = new BasicTracerProvider({
    resource: resourceFromAttributes({
      [ATTR_SERVICE_NAME]: serviceName,
    }),
    spanProcessors: [new BatchSpanProcessor(exporter)],
  });

  trace.setGlobalTracerProvider(provider);
  started = true;
};

export const withSpan = async <T>(
  name: string,
  attributes: Record<string, string | number | boolean | undefined>,
  operation: () => Promise<T>,
) => {
  const tracer = trace.getTracer("podwatch");

  return tracer.startActiveSpan(name, async (span) => {
    Object.entries(attributes).forEach(([key, value]) => {
      if (value !== undefined) {
        span.setAttribute(key, value);
      }
    });

    try {
      const result = await operation();
      span.setStatus({ code: SpanStatusCode.OK });

      return result;
    } catch (error) {
      span.recordException(
        error instanceof Error ? error : new Error(String(error)),
      );
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error instanceof Error ? error.message : "Unknown error",
      });

      throw error;
    } finally {
      span.end();
    }
  });
};
