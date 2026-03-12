import {
  chat,
  type ModelMessage,
  toServerSentEventsResponse,
} from "@tanstack/ai";
import { openaiText } from "@tanstack/ai-openai";
import { createFileRoute } from "@tanstack/react-router";
import { Effect } from "effect";

export const Route = createFileRoute("/api/ai/chat")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const [
          { auth },
          { ensureServerBooted },
          { getDatabase, createPodwatchRepository },
          { loadDashboardWorkflow },
          { buildCoachPrompt },
          { withSpan },
        ] = await Promise.all([
          import("#/server/auth"),
          import("#/server/bootstrap"),
          import("@podwatch/db"),
          import("@podwatch/domain"),
          import("#/server/coach-workflow"),
          import("@podwatch/observability"),
        ]);

        ensureServerBooted();

        const session = await auth.api.getSession({
          headers: request.headers,
        });

        if (!session?.user) {
          return new Response("Unauthorized", { status: 401 });
        }

        const model = process.env.AI_MODEL as
          | Parameters<typeof openaiText>[0]
          | undefined;

        if (!process.env.OPENAI_API_KEY || !model) {
          return new Response(
            "AI is not configured. Set OPENAI_API_KEY and AI_MODEL.",
            {
              status: 503,
            },
          );
        }

        const body = (await request.json()) as {
          messages?: Array<ModelMessage>;
        };

        const messages = normalizeMessages(body.messages ?? []);
        const repository = createPodwatchRepository(getDatabase());

        return withSpan(
          "ai.coach.chat",
          {
            "podwatch.user_id": session.user.id,
          },
          async () => {
            const dashboard = await Effect.runPromise(
              loadDashboardWorkflow(repository, session.user.id),
            );
            const promptBundle = await buildCoachPrompt({
              userPrompt: getLatestUserPrompt(messages),
              dashboard,
            });
            const stream = chat({
              adapter: openaiText(model),
              messages,
              systemPrompts: [promptBundle.systemPrompt],
              temperature: 0.3,
            });

            return toServerSentEventsResponse(stream);
          },
        );
      },
    },
  },
});

const getLatestUserPrompt = (messages: Array<ModelMessage>) => {
  const lastUserMessage = [...messages]
    .reverse()
    .find((message) => message.role === "user");

  if (!lastUserMessage) {
    return "Review the board and recommend the next scheduling move.";
  }

  if (typeof lastUserMessage.content === "string") {
    return lastUserMessage.content;
  }

  if (Array.isArray(lastUserMessage.content)) {
    const text = lastUserMessage.content
      .map((part) => {
        if (typeof part === "string") {
          return part;
        }

        if (
          typeof part === "object" &&
          part !== null &&
          "type" in part &&
          part.type === "text" &&
          "content" in part
        ) {
          return String(part.content);
        }

        return "";
      })
      .join(" ")
      .trim();

    if (text) {
      return text;
    }
  }

  return "Review the board and recommend the next scheduling move.";
};

const readModelMessageText = (content: ModelMessage["content"]) => {
  if (typeof content === "string") {
    return content.trim() || null;
  }

  if (content === null) {
    return null;
  }

  const text = content
    .filter((part) => part.type === "text")
    .map((part) => part.content)
    .join(" ")
    .trim();

  return text || null;
};

const normalizeMessages = (messages: Array<ModelMessage>) =>
  messages.flatMap((message): Array<ModelMessage<string | null>> => {
    if (message.role === "tool") {
      return [];
    }

    const content = readModelMessageText(message.content);

    if (!content) {
      return [];
    }

    return [
      {
        role: message.role,
        content,
      },
    ];
  });
