import { Temporal } from "@js-temporal/polyfill";
import { Effect, Schema } from "effect";

import {
  type CreateEventInput,
  CreateEventInputSchema,
  type CreatePodInput,
  CreatePodInputSchema,
  type DashboardSnapshot,
  DashboardSnapshotSchema,
  type EventSummary,
  type PodSummary,
  type PodwatchRepository,
} from "./contracts";
import {
  conflictError,
  formatPodwatchError,
  infrastructureError,
  notFoundError,
  type PodwatchError,
  validationError,
} from "./errors";

const decodeCreatePodInput = Schema.decodeUnknown(CreatePodInputSchema);
const decodeCreateEventInput = Schema.decodeUnknown(CreateEventInputSchema);
const decodeDashboardSnapshot = Schema.decodeUnknown(DashboardSnapshotSchema);

const collapseWhitespace = (value: string) => value.trim().replace(/\s+/g, " ");

const sanitizeOptionalText = (
  value: string,
  maxLength: number,
  label: string,
) => {
  const normalized = value.trim();

  if (normalized.length > maxLength) {
    return Effect.fail(
      validationError(`${label} must be ${maxLength} characters or fewer.`),
    );
  }

  return Effect.succeed(normalized);
};

const sanitizeRequiredText = (
  value: string,
  {
    label,
    minLength,
    maxLength,
  }: {
    label: string;
    minLength: number;
    maxLength: number;
  },
) => {
  const normalized = collapseWhitespace(value);

  if (normalized.length < minLength) {
    return Effect.fail(
      validationError(`${label} must be at least ${minLength} characters.`),
    );
  }

  if (normalized.length > maxLength) {
    return Effect.fail(
      validationError(`${label} must be ${maxLength} characters or fewer.`),
    );
  }

  return Effect.succeed(normalized);
};

const validateTimezone = (timezone: string) => {
  const normalized = timezone.trim();

  if (!normalized) {
    return Effect.fail(validationError("A browser timezone is required."));
  }

  return Effect.try({
    try: () => {
      new Intl.DateTimeFormat("en-US", { timeZone: normalized }).format(
        new Date(),
      );
      return normalized;
    },
    catch: () => validationError("Submit a valid timezone."),
  });
};

const parseLocalDateTime = (scheduledFor: string, timezone: string) =>
  Effect.try({
    try: () => {
      const plainDateTime = Temporal.PlainDateTime.from(scheduledFor);
      const zonedDateTime = plainDateTime.toZonedDateTime(timezone);

      return new Date(zonedDateTime.toInstant().epochMilliseconds);
    },
    catch: () => validationError("Submit a valid local date and time."),
  });

const repositoryFailure =
  (message: string) =>
  (error: unknown): PodwatchError => {
    const formatted = formatPodwatchError(error);

    if (formatted._tag !== "InfrastructureError") {
      return formatted;
    }

    return infrastructureError(message);
  };

const fromRepository = <T>(message: string, run: () => Promise<T>) =>
  Effect.tryPromise({
    try: run,
    catch: repositoryFailure(message),
  });

export const loadDashboardWorkflow = (
  repository: PodwatchRepository,
  userId: string,
  now = new Date(),
) =>
  fromRepository("Could not load the dashboard.", () =>
    repository.loadDashboardSnapshot(userId, now),
  ).pipe(
    Effect.flatMap((snapshot) =>
      decodeDashboardSnapshot(snapshot).pipe(
        Effect.mapError(() =>
          infrastructureError(
            "Dashboard data did not match the expected contract.",
          ),
        ),
      ),
    ),
  );

export const createPodWorkflow = (
  repository: PodwatchRepository,
  userId: string,
  rawInput: unknown,
) =>
  Effect.gen(function* () {
    const input = (yield* decodeCreatePodInput(rawInput).pipe(
      Effect.mapError(() => validationError("Submit a valid pod payload.")),
    )) as CreatePodInput;

    const name = yield* sanitizeRequiredText(input.name, {
      label: "Pod name",
      minLength: 2,
      maxLength: 120,
    });
    const description = yield* sanitizeOptionalText(
      input.description,
      1000,
      "Description",
    );
    const nameNormalized = name.toLocaleLowerCase();

    const existing = yield* fromRepository(
      "Could not check for existing pods.",
      () => repository.findPodByNormalizedName(userId, nameNormalized),
    );

    if (existing) {
      return yield* Effect.fail(
        conflictError("A pod with this name already exists."),
      );
    }

    return yield* fromRepository("Could not create the pod.", () =>
      repository.createPod({
        userId,
        name,
        nameNormalized,
        description,
      }),
    );
  });

export const createEventWorkflow = (
  repository: PodwatchRepository,
  userId: string,
  rawInput: unknown,
) =>
  Effect.gen(function* () {
    const input = (yield* decodeCreateEventInput(rawInput).pipe(
      Effect.mapError(() => validationError("Submit a valid event payload.")),
    )) as CreateEventInput;

    const podId = input.podId.trim();

    if (!podId) {
      return yield* Effect.fail(
        validationError("Choose a pod before scheduling."),
      );
    }

    const timezone = yield* validateTimezone(input.timezone);
    const title = yield* sanitizeRequiredText(input.title, {
      label: "Event title",
      minLength: 2,
      maxLength: 255,
    });
    const location = yield* sanitizeOptionalText(
      input.location,
      255,
      "Location",
    );
    const description = yield* sanitizeOptionalText(
      input.description,
      2000,
      "Description",
    );
    const scheduledFor = yield* parseLocalDateTime(
      input.scheduledFor,
      timezone,
    );

    const pod = yield* fromRepository("Could not load the selected pod.", () =>
      repository.findPodForOwner(userId, podId),
    );

    if (!pod) {
      return yield* Effect.fail(
        notFoundError("That pod does not exist for the current user."),
      );
    }

    return yield* fromRepository("Could not schedule the event.", () =>
      repository.createEvent({
        userId,
        podId: pod.id,
        title,
        description,
        location,
        scheduledFor,
        scheduledTimezone: timezone,
      }),
    );
  });

export const createCoachBrief = (snapshot: DashboardSnapshot) => {
  const podLines =
    snapshot.pods.length === 0
      ? ["- No pods exist yet."]
      : snapshot.pods.map(
          (pod) => `- ${pod.name}: ${pod.eventCount} scheduled event(s).`,
        );

  const eventLines =
    snapshot.events.length === 0
      ? ["- No recent or upcoming events."]
      : snapshot.events.slice(0, 8).map((event) => {
          const when = event.scheduledFor;
          const where = event.location ? ` at ${event.location}` : "";

          return `- ${event.title} for ${event.podName} on ${when}${where}.`;
        });

  return [
    `Pods tracked: ${snapshot.summary.podCount}`,
    `Events scheduled: ${snapshot.summary.eventCount}`,
    `Upcoming events: ${snapshot.summary.upcomingCount}`,
    "Pods:",
    ...podLines,
    "Timeline:",
    ...eventLines,
  ].join("\n");
};

export type { DashboardSnapshot, EventSummary, PodSummary };
