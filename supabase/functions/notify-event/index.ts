import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.93.3";

type NotifyEventPayload = {
  eventId: string;
  actorId: string;
  type:
    | "event_created"
    | "schedule_changed"
    | "arrival_update"
    | "eta_update"
    | "event_cancelled";
  arrival?: "not_sure" | "on_the_way" | "arrived" | "late";
  etaMinutes?: number | null;
  changedFields?: string[];
  cancelReason?: string | null;
};

const allowedNotifyTypes: NotifyEventPayload["type"][] = [
  "event_created",
  "schedule_changed",
  "arrival_update",
  "eta_update",
  "event_cancelled",
];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function formatEventTime(startsAt: string, endsAt?: string | null) {
  const start = new Date(startsAt);
  const dateLabel = new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(start);
  const timeLabel = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(start);

  if (!endsAt) {
    return `${dateLabel} · ${timeLabel}`;
  }

  const end = new Date(endsAt);
  const endTime = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(end);

  return `${dateLabel} · ${timeLabel}–${endTime}`;
}

function buildArrivalLabel(arrival?: NotifyEventPayload["arrival"]) {
  if (arrival === "on_the_way") return "on the way";
  if (arrival === "arrived") return "here";
  if (arrival === "late") return "running late";
  return "unsure";
}

function displayNameFromProfile(profile?: {
  display_name?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  email?: string | null;
}) {
  if (!profile) return "Someone";
  if (profile.display_name) return profile.display_name;
  const fullName = [profile.first_name, profile.last_name].filter(Boolean).join(" ");
  if (fullName) return fullName;
  if (profile.email) return profile.email.split("@")[0];
  return "Someone";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: "Missing Supabase env vars." }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseAuth = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    const {
      data: { user },
      error: authError,
    } = await supabaseAuth.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = (await req.json()) as NotifyEventPayload;

    if (!payload?.eventId || !payload?.actorId || !payload?.type) {
      return new Response(JSON.stringify({ error: "Missing payload fields." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!allowedNotifyTypes.includes(payload.type)) {
      return new Response(JSON.stringify({ error: "Invalid notification type." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (payload.actorId !== user.id) {
      return new Response(JSON.stringify({ error: "Actor mismatch." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: eventRow, error: eventError } = await supabaseAdmin
      .from("events")
      .select("id,pod_id,title,starts_at,ends_at,location_text")
      .eq("id", payload.eventId)
      .maybeSingle();

    if (eventError || !eventRow) {
      return new Response(JSON.stringify({ error: "Event not found." }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: membershipRow, error: membershipError } = await supabaseAdmin
      .from("pod_memberships")
      .select("user_id")
      .eq("pod_id", eventRow.pod_id)
      .eq("user_id", user.id)
      .eq("is_active", true)
      .maybeSingle();

    if (membershipError || !membershipRow) {
      return new Response(JSON.stringify({ error: "Forbidden." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: profileRow } = await supabaseAdmin
      .from("profiles")
      .select("display_name,first_name,last_name,email")
      .eq("id", payload.actorId)
      .maybeSingle();

    const actorName = displayNameFromProfile(profileRow ?? undefined);

    let recipientIds: string[] = [];

    if (payload.type === "event_created" || payload.type === "event_cancelled") {
      const { data: members } = await supabaseAdmin
        .from("pod_memberships")
        .select("user_id")
        .eq("pod_id", eventRow.pod_id)
        .eq("is_active", true);

      recipientIds = (members ?? [])
        .map((member) => member.user_id)
        .filter((userId) => userId && userId !== payload.actorId);
    } else {
      const { data: attendees } = await supabaseAdmin
        .from("event_attendance")
        .select("user_id")
        .eq("event_id", payload.eventId)
        .in("rsvp", ["yes", "maybe"]);

      recipientIds = (attendees ?? [])
        .map((attendee) => attendee.user_id)
        .filter((userId) => userId && userId !== payload.actorId);
    }

    recipientIds = Array.from(new Set(recipientIds));

    if (recipientIds.length === 0) {
      return new Response(JSON.stringify({ ok: true, delivered: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const eventTime = formatEventTime(eventRow.starts_at, eventRow.ends_at);
    const locationLabel = eventRow.location_text ?? "Location TBD";
    const hasEtaMinutes = typeof payload.etaMinutes === "number";

    let title = "";
    let body = "";

    if (payload.type === "event_created") {
      title = `New event: ${eventRow.title}`;
      body = `${eventTime} · ${locationLabel}`;
    } else if (payload.type === "schedule_changed") {
      title = `Schedule updated: ${eventRow.title}`;
      const changeLabel = payload.changedFields?.length
        ? `Changed ${payload.changedFields.join(", ")}.`
        : "Details updated.";
      body = `${changeLabel} ${eventTime} · ${locationLabel}`;
    } else if (payload.type === "eta_update") {
      title = `${actorName} shared an ETA`;
      body = hasEtaMinutes
        ? `${payload.etaMinutes} min to ${eventRow.title}`
        : `${actorName} updated their ETA.`;
    } else if (payload.type === "event_cancelled") {
      title = `Canceled: ${eventRow.title}`;
      body = payload.cancelReason ? payload.cancelReason : `${actorName} canceled this event.`;
    } else {
      title = `${actorName} is ${buildArrivalLabel(payload.arrival)}`;
      body = hasEtaMinutes
        ? `ETA ${payload.etaMinutes} min · ${eventRow.title}`
        : eventRow.title;
    }

    const notificationRows = recipientIds.map((recipientId) => ({
      recipient_id: recipientId,
      actor_id: payload.actorId,
      pod_id: eventRow.pod_id,
      event_id: eventRow.id,
      type: payload.type,
      title,
      body,
      data: {
        arrival: payload.arrival ?? null,
        eta_minutes: payload.etaMinutes ?? null,
        changed_fields: payload.changedFields ?? [],
        cancel_reason: payload.cancelReason ?? null,
      },
    }));

    const { error: insertError } = await supabaseAdmin
      .from("notifications")
      .insert(notificationRows);

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: tokenRows } = await supabaseAdmin
      .from("user_push_tokens")
      .select("token")
      .in("user_id", recipientIds);

    const tokens = (tokenRows ?? []).map((row) => row.token).filter(Boolean);

    if (tokens.length > 0) {
      const messages = tokens.map((token) => ({
        to: token,
        sound: "default",
        title,
        body,
        data: {
          eventId: eventRow.id,
          type: payload.type,
        },
      }));

      const chunks: typeof messages[] = [];
      for (let i = 0; i < messages.length; i += 100) {
        chunks.push(messages.slice(i, i + 100));
      }

      for (const chunk of chunks) {
        await fetch("https://exp.host/--/api/v2/push/send", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(chunk),
        });
      }
    }

    return new Response(JSON.stringify({ ok: true, delivered: recipientIds.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unexpected error.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
