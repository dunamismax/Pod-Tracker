import { Effect } from "effect";
import { describe, expect, it } from "vitest";

import type {
  DashboardSnapshot,
  PodSummary,
  PodwatchRepository,
} from "./contracts";
import { createEventWorkflow, createPodWorkflow } from "./workflows";

const emptySnapshot: DashboardSnapshot = {
  summary: {
    podCount: 0,
    eventCount: 0,
    upcomingCount: 0,
  },
  pods: [],
  events: [],
};

const createRepository = (
  overrides: Partial<PodwatchRepository> = {},
): PodwatchRepository => ({
  loadDashboardSnapshot: async () => emptySnapshot,
  findPodByNormalizedName: async () => null,
  createPod: async ({ name, description }) => ({
    id: "pod_1",
    name,
    description,
    eventCount: 0,
  }),
  findPodForOwner: async () =>
    ({
      id: "pod_1",
      name: "Friday Pod",
    }) satisfies Pick<PodSummary, "id" | "name">,
  createEvent: async ({
    title,
    description,
    location,
    podId,
    scheduledFor,
    scheduledTimezone,
  }) => ({
    id: "event_1",
    podId,
    podName: "Friday Pod",
    title,
    description,
    location,
    scheduledFor: scheduledFor.toISOString(),
    scheduledTimezone,
  }),
  ...overrides,
});

describe("createPodWorkflow", () => {
  it("rejects duplicate pods after normalization", async () => {
    const repository = createRepository({
      findPodByNormalizedName: async () => ({
        id: "pod_1",
        name: "Friday Pod",
        description: "",
        eventCount: 0,
      }),
    });

    const result = await Effect.runPromiseExit(
      createPodWorkflow(repository, "user_1", {
        name: "  friday   pod ",
        description: "",
      }),
    );

    expect(result._tag).toBe("Failure");
  });

  it("normalizes pod names before persisting", async () => {
    let createdName = "";

    const repository = createRepository({
      createPod: async ({ name, description }) => {
        createdName = name;

        return {
          id: "pod_1",
          name,
          description,
          eventCount: 0,
        };
      },
    });

    const result = await Effect.runPromise(
      createPodWorkflow(repository, "user_1", {
        name: "  Friday   Pod ",
        description: "Team sync",
      }),
    );

    expect(result.name).toBe("Friday Pod");
    expect(createdName).toBe("Friday Pod");
  });
});

describe("createEventWorkflow", () => {
  it("converts browser-local time to UTC", async () => {
    const repository = createRepository();

    const event = await Effect.runPromise(
      createEventWorkflow(repository, "user_1", {
        podId: "pod_1",
        title: "Summer Meetup",
        description: "Bring water",
        location: "Community center",
        scheduledFor: "2026-07-10T19:00",
        timezone: "America/Phoenix",
      }),
    );

    expect(event.scheduledFor).toBe("2026-07-11T02:00:00.000Z");
  });
});
