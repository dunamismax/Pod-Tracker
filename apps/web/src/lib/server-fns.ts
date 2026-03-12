import type {
  DashboardSnapshot,
  EventSummary,
  PodSummary,
} from "@podwatch/domain";
import { createServerFn } from "@tanstack/react-start";
import { Effect } from "effect";

export type Viewer = {
  id: string;
  name: string;
  email: string;
  image: string | null;
};

export type MutationResult<T> =
  | {
      ok: true;
      message: string;
      data: T;
    }
  | {
      ok: false;
      error: string;
    };

const requireViewer = async () => {
  const [{ getRequestHeaders }, { auth }, { ensureServerBooted }] =
    await Promise.all([
      import("@tanstack/react-start/server"),
      import("#/server/auth"),
      import("#/server/bootstrap"),
    ]);

  ensureServerBooted();

  const session = await auth.api.getSession({
    headers: getRequestHeaders(),
  });

  if (!session?.user) {
    throw new Error("Unauthorized");
  }

  return session.user;
};

const runMutation = async <T>(
  operation: () => Promise<T>,
  message: string,
): Promise<MutationResult<T>> => {
  try {
    const data = await operation();

    return {
      ok: true,
      message,
      data,
    };
  } catch (error) {
    return {
      ok: false,
      error:
        error instanceof Error ? error.message : "Unexpected server failure.",
    };
  }
};

export const getViewer = createServerFn({ method: "GET" }).handler(
  async (): Promise<Viewer | null> => {
    const [{ getRequestHeaders }, { auth }, { ensureServerBooted }] =
      await Promise.all([
        import("@tanstack/react-start/server"),
        import("#/server/auth"),
        import("#/server/bootstrap"),
      ]);

    ensureServerBooted();

    const session = await auth.api.getSession({
      headers: getRequestHeaders(),
    });

    if (!session?.user) {
      return null;
    }

    return {
      id: session.user.id,
      name: session.user.name,
      email: session.user.email,
      image: session.user.image ?? null,
    };
  },
);

export const getDashboard = createServerFn({ method: "GET" }).handler(
  async (): Promise<DashboardSnapshot> => {
    const user = await requireViewer();
    const [
      { getDatabase, createPodwatchRepository },
      { loadDashboardWorkflow },
      { withSpan },
    ] = await Promise.all([
      import("@podwatch/db"),
      import("@podwatch/domain"),
      import("@podwatch/observability"),
    ]);

    const repository = createPodwatchRepository(getDatabase());

    return withSpan(
      "dashboard.load",
      {
        "podwatch.user_id": user.id,
      },
      async () => Effect.runPromise(loadDashboardWorkflow(repository, user.id)),
    );
  },
);

export const createPod = createServerFn({ method: "POST" })
  .inputValidator(
    (input: unknown) => input as { name: string; description: string },
  )
  .handler(async ({ data }): Promise<MutationResult<PodSummary>> => {
    const user = await requireViewer();
    const [
      { getDatabase, createPodwatchRepository },
      { createPodWorkflow },
      { withSpan },
    ] = await Promise.all([
      import("@podwatch/db"),
      import("@podwatch/domain"),
      import("@podwatch/observability"),
    ]);

    const repository = createPodwatchRepository(getDatabase());

    return withSpan(
      "pod.create",
      {
        "podwatch.user_id": user.id,
      },
      () =>
        runMutation(
          async () =>
            Effect.runPromise(createPodWorkflow(repository, user.id, data)),
          "Pod created.",
        ),
    );
  });

export const createEvent = createServerFn({ method: "POST" })
  .inputValidator(
    (input: unknown) =>
      input as {
        podId: string;
        title: string;
        description: string;
        location: string;
        scheduledFor: string;
        timezone: string;
      },
  )
  .handler(async ({ data }): Promise<MutationResult<EventSummary>> => {
    const user = await requireViewer();
    const [
      { getDatabase, createPodwatchRepository },
      { createEventWorkflow },
      { withSpan },
    ] = await Promise.all([
      import("@podwatch/db"),
      import("@podwatch/domain"),
      import("@podwatch/observability"),
    ]);

    const repository = createPodwatchRepository(getDatabase());

    return withSpan(
      "event.create",
      {
        "podwatch.user_id": user.id,
      },
      () =>
        runMutation(
          async () =>
            Effect.runPromise(createEventWorkflow(repository, user.id, data)),
          "Event scheduled.",
        ),
    );
  });
