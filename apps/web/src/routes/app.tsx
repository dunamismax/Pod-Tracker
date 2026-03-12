import {
  useMutation,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query";
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { startTransition, useState } from "react";

import { DashboardView } from "#/components/dashboard-view";
import { authClient } from "#/lib/auth-client";
import { dashboardQueryOptions, viewerQueryOptions } from "#/lib/query";
import { createEvent, createPod, getViewer } from "#/lib/server-fns";
import { useBrowserTimeZone } from "#/lib/timezone";

export const Route = createFileRoute("/app")({
  beforeLoad: async () => {
    const viewer = await getViewer();

    if (!viewer) {
      throw redirect({ to: "/login" });
    }
  },
  loader: ({ context }) =>
    Promise.all([
      context.queryClient.ensureQueryData(viewerQueryOptions()),
      context.queryClient.ensureQueryData(dashboardQueryOptions()),
    ]),
  component: AppPage,
});

function AppPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const timezone = useBrowserTimeZone();
  const viewerQuery = useSuspenseQuery(viewerQueryOptions());
  const dashboardQuery = useSuspenseQuery(dashboardQueryOptions());
  const [podForm, setPodForm] = useState({
    name: "",
    description: "",
  });
  const [eventForm, setEventForm] = useState({
    podId: "",
    title: "",
    location: "",
    scheduledFor: "",
    description: "",
  });
  const [podResult, setPodResult] = useState<Awaited<
    ReturnType<typeof createPod>
  > | null>(null);
  const [eventResult, setEventResult] = useState<Awaited<
    ReturnType<typeof createEvent>
  > | null>(null);

  const podMutation = useMutation({
    mutationFn: (data: { name: string; description: string }) =>
      createPod({ data }),
    onSuccess: async (result) => {
      setPodResult(result);

      if (!result.ok) {
        return;
      }

      startTransition(() => {
        setPodForm({
          name: "",
          description: "",
        });
      });

      await queryClient.invalidateQueries({ queryKey: ["dashboard"] });
    },
  });

  const eventMutation = useMutation({
    mutationFn: (data: {
      podId: string;
      title: string;
      description: string;
      location: string;
      scheduledFor: string;
      timezone: string;
    }) => createEvent({ data }),
    onSuccess: async (result) => {
      setEventResult(result);

      if (!result.ok) {
        return;
      }

      startTransition(() => {
        setEventForm({
          podId: "",
          title: "",
          location: "",
          scheduledFor: "",
          description: "",
        });
      });

      await queryClient.invalidateQueries({ queryKey: ["dashboard"] });
    },
  });

  const handleSignOut = async () => {
    await authClient.signOut();
    await queryClient.invalidateQueries({ queryKey: ["viewer"] });
    await navigate({ to: "/" });
  };

  if (!viewerQuery.data) {
    throw redirect({ to: "/login" });
  }

  return (
    <DashboardView
      viewer={viewerQuery.data}
      snapshot={dashboardQuery.data}
      timezone={timezone}
      podForm={podForm}
      eventForm={eventForm}
      podResult={podResult}
      eventResult={eventResult}
      isCreatingPod={podMutation.isPending}
      isCreatingEvent={eventMutation.isPending}
      onPodFormChange={setPodForm}
      onEventFormChange={setEventForm}
      onPodSubmit={(event) => {
        event.preventDefault();
        void podMutation.mutateAsync(podForm);
      }}
      onEventSubmit={(event) => {
        event.preventDefault();
        void eventMutation.mutateAsync({
          ...eventForm,
          timezone,
        });
      }}
      onSignOut={() => {
        void handleSignOut();
      }}
    />
  );
}
