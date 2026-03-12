import { Schema } from "effect";

export const SummarySchema = Schema.Struct({
  podCount: Schema.Number,
  eventCount: Schema.Number,
  upcomingCount: Schema.Number,
});

export const PodSummarySchema = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  description: Schema.String,
  eventCount: Schema.Number,
});

export const EventSummarySchema = Schema.Struct({
  id: Schema.String,
  podId: Schema.String,
  podName: Schema.String,
  title: Schema.String,
  description: Schema.String,
  location: Schema.String,
  scheduledFor: Schema.String,
  scheduledTimezone: Schema.String,
});

export const DashboardSnapshotSchema = Schema.Struct({
  summary: SummarySchema,
  pods: Schema.Array(PodSummarySchema),
  events: Schema.Array(EventSummarySchema),
});

export const CreatePodInputSchema = Schema.Struct({
  name: Schema.String,
  description: Schema.String,
});

export const CreateEventInputSchema = Schema.Struct({
  podId: Schema.String,
  title: Schema.String,
  description: Schema.String,
  location: Schema.String,
  scheduledFor: Schema.String,
  timezone: Schema.String,
});

export type Summary = typeof SummarySchema.Type;
export type PodSummary = typeof PodSummarySchema.Type;
export type EventSummary = typeof EventSummarySchema.Type;
export type DashboardSnapshot = typeof DashboardSnapshotSchema.Type;
export type CreatePodInput = typeof CreatePodInputSchema.Type;
export type CreateEventInput = typeof CreateEventInputSchema.Type;

export interface PodwatchRepository {
  loadDashboardSnapshot(userId: string, now: Date): Promise<DashboardSnapshot>;
  findPodByNormalizedName(
    userId: string,
    nameNormalized: string,
  ): Promise<PodSummary | null>;
  createPod(input: {
    userId: string;
    name: string;
    nameNormalized: string;
    description: string;
  }): Promise<PodSummary>;
  findPodForOwner(
    userId: string,
    podId: string,
  ): Promise<Pick<PodSummary, "id" | "name"> | null>;
  createEvent(input: {
    userId: string;
    podId: string;
    title: string;
    description: string;
    location: string;
    scheduledFor: Date;
    scheduledTimezone: string;
  }): Promise<EventSummary>;
}
