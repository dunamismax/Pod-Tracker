import type {
  DashboardSnapshot,
  EventSummary,
  PodSummary,
  PodwatchRepository,
} from "@podwatch/domain";
import { and, asc, count, eq, gte } from "drizzle-orm";

import type { PodwatchDatabase } from "./client";
import { events, pods } from "./schema";

const toIsoString = (value: Date) => value.toISOString();

export const createPodwatchRepository = (
  db: PodwatchDatabase,
): PodwatchRepository => ({
  async loadDashboardSnapshot(userId, now) {
    const recentThreshold = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    const [
      podRows,
      eventRows,
      totalPodsRow,
      totalEventsRow,
      upcomingEventsRow,
    ] = await Promise.all([
      db
        .select({
          id: pods.id,
          name: pods.name,
          description: pods.description,
          eventCount: count(events.id),
        })
        .from(pods)
        .leftJoin(events, eq(events.podId, pods.id))
        .where(eq(pods.ownerId, userId))
        .groupBy(pods.id, pods.name, pods.description)
        .orderBy(asc(pods.name)),
      db
        .select({
          id: events.id,
          podId: events.podId,
          podName: pods.name,
          title: events.title,
          description: events.description,
          location: events.location,
          scheduledFor: events.scheduledFor,
          scheduledTimezone: events.scheduledTimezone,
        })
        .from(events)
        .innerJoin(pods, eq(events.podId, pods.id))
        .where(
          and(
            eq(events.ownerId, userId),
            gte(events.scheduledFor, recentThreshold),
          ),
        )
        .orderBy(asc(events.scheduledFor), asc(events.title))
        .limit(20),
      db
        .select({
          count: count(),
        })
        .from(pods)
        .where(eq(pods.ownerId, userId)),
      db
        .select({
          count: count(),
        })
        .from(events)
        .where(eq(events.ownerId, userId)),
      db
        .select({
          count: count(),
        })
        .from(events)
        .where(and(eq(events.ownerId, userId), gte(events.scheduledFor, now))),
    ]);

    return {
      summary: {
        podCount: totalPodsRow[0]?.count ?? 0,
        eventCount: totalEventsRow[0]?.count ?? 0,
        upcomingCount: upcomingEventsRow[0]?.count ?? 0,
      },
      pods: podRows.map(
        (pod): PodSummary => ({
          id: pod.id,
          name: pod.name,
          description: pod.description,
          eventCount: pod.eventCount,
        }),
      ),
      events: eventRows.map(
        (event): EventSummary => ({
          id: event.id,
          podId: event.podId,
          podName: event.podName,
          title: event.title,
          description: event.description,
          location: event.location,
          scheduledFor: toIsoString(event.scheduledFor),
          scheduledTimezone: event.scheduledTimezone,
        }),
      ),
    } satisfies DashboardSnapshot;
  },

  async findPodByNormalizedName(userId, nameNormalized) {
    const row = await db.query.pods.findFirst({
      where: and(
        eq(pods.ownerId, userId),
        eq(pods.nameNormalized, nameNormalized),
      ),
    });

    if (!row) {
      return null;
    }

    const eventCountRow = await db
      .select({
        count: count(),
      })
      .from(events)
      .where(eq(events.podId, row.id));

    return {
      id: row.id,
      name: row.name,
      description: row.description,
      eventCount: eventCountRow[0]?.count ?? 0,
    };
  },

  async createPod({ userId, name, nameNormalized, description }) {
    const [row] = await db
      .insert(pods)
      .values({
        ownerId: userId,
        name,
        nameNormalized,
        description,
      })
      .returning();

    if (!row) {
      throw new Error("Failed to create pod.");
    }

    return {
      id: row.id,
      name: row.name,
      description: row.description,
      eventCount: 0,
    };
  },

  async findPodForOwner(userId, podId) {
    const row = await db.query.pods.findFirst({
      columns: {
        id: true,
        name: true,
      },
      where: and(eq(pods.id, podId), eq(pods.ownerId, userId)),
    });

    if (!row) {
      return null;
    }

    return row;
  },

  async createEvent({
    userId,
    podId,
    title,
    description,
    location,
    scheduledFor,
    scheduledTimezone,
  }) {
    const [row] = await db
      .insert(events)
      .values({
        ownerId: userId,
        podId,
        title,
        description,
        location,
        scheduledFor,
        scheduledTimezone,
      })
      .returning({
        id: events.id,
        podId: events.podId,
        title: events.title,
        description: events.description,
        location: events.location,
        scheduledFor: events.scheduledFor,
        scheduledTimezone: events.scheduledTimezone,
      });

    if (!row) {
      throw new Error("Failed to create event.");
    }

    const podRow = await db
      .select({
        podName: pods.name,
      })
      .from(pods)
      .where(eq(pods.id, podId))
      .limit(1);

    return {
      id: row.id,
      podId: row.podId,
      podName: podRow[0]?.podName ?? "Pod",
      title: row.title,
      description: row.description,
      location: row.location,
      scheduledFor: toIsoString(row.scheduledFor),
      scheduledTimezone: row.scheduledTimezone,
    };
  },
});
