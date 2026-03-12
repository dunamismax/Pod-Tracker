import { createStep, createWorkflow } from "@mastra/core/workflows";
import { createCoachBrief, type DashboardSnapshot } from "@podwatch/domain";
import { z } from "zod";

const dashboardSnapshotSchema = z.object({
  summary: z.object({
    podCount: z.number(),
    eventCount: z.number(),
    upcomingCount: z.number(),
  }),
  pods: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      description: z.string(),
      eventCount: z.number(),
    }),
  ),
  events: z.array(
    z.object({
      id: z.string(),
      podId: z.string(),
      podName: z.string(),
      title: z.string(),
      description: z.string(),
      location: z.string(),
      scheduledFor: z.string(),
      scheduledTimezone: z.string(),
    }),
  ),
});

const inputSchema = z.object({
  userPrompt: z.string(),
  dashboard: dashboardSnapshotSchema,
});

const outputSchema = z.object({
  contextBrief: z.string(),
  systemPrompt: z.string(),
});

const coachPromptStep = createStep({
  id: "coach-prompt",
  inputSchema,
  outputSchema,
  description:
    "Turn the current dashboard snapshot into grounded coaching context.",
  execute: async ({ inputData }) => {
    const contextBrief = createCoachBrief(
      inputData.dashboard as DashboardSnapshot,
    );

    return {
      contextBrief,
      systemPrompt: [
        "You are PodWatch's schedule coach.",
        "Base every answer on the dashboard context that follows.",
        "Be concise, operational, and specific about what the user should do next.",
        "If the board lacks enough information, say exactly what is missing instead of guessing.",
        `Current user request: ${inputData.userPrompt}`,
        "Dashboard context:",
        contextBrief,
      ].join("\n\n"),
    };
  },
});

const coachWorkflow = createWorkflow({
  id: "podwatch-coach",
  inputSchema,
  outputSchema,
})
  .then(coachPromptStep)
  .commit();

export const buildCoachPrompt = async ({
  userPrompt,
  dashboard,
}: {
  userPrompt: string;
  dashboard: DashboardSnapshot;
}): Promise<{ contextBrief: string; systemPrompt: string }> => {
  const run = await coachWorkflow.createRun();
  const result = await run.start({
    inputData: {
      userPrompt,
      dashboard,
    },
  });

  if (result.status !== "success") {
    throw new Error("Could not prepare AI coaching context.");
  }

  return result.result as { contextBrief: string; systemPrompt: string };
};
