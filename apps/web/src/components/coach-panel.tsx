import { fetchServerSentEvents } from "@tanstack/ai-client";
import { useChat } from "@tanstack/ai-react";
import { LoaderCircle, SendHorizontal, Sparkles } from "lucide-react";
import { useState } from "react";

const readMessageText = (parts: Array<{ type: string; content?: string }>) =>
  parts
    .filter((part) => part.type === "text" && typeof part.content === "string")
    .map((part) => part.content)
    .join("")
    .trim();

export function CoachPanel() {
  const [input, setInput] = useState("");
  const { messages, sendMessage, isLoading, error } = useChat({
    connection: fetchServerSentEvents("/api/ai/chat", {
      credentials: "include",
    }),
  });

  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!input.trim()) {
      return;
    }

    const nextMessage = input;
    setInput("");
    await sendMessage(nextMessage);
  };

  return (
    <div className="coach-chat">
      <div className="coach-intro">
        <Sparkles size={18} />
        <p>
          Ask for a next-step recommendation, a schedule cleanup pass, or a
          quick read on which pod needs attention first.
        </p>
      </div>

      <div className="coach-thread">
        {messages.length === 0 ? (
          <div className="bubble bubble-assistant">
            <strong>Coach</strong>
            <p>
              Try “What should I schedule next?” or “Which pod looks
              underscheduled?”
            </p>
          </div>
        ) : null}

        {messages
          .filter((message) => message.role !== "system")
          .map((message) => {
            const text = readMessageText(
              message.parts as Array<{ type: string; content?: string }>,
            );

            if (!text) {
              return null;
            }

            return (
              <div
                key={message.id}
                className={
                  message.role === "user"
                    ? "bubble bubble-user"
                    : "bubble bubble-assistant"
                }
              >
                <strong>{message.role === "user" ? "You" : "Coach"}</strong>
                <p>{text}</p>
              </div>
            );
          })}

        {isLoading ? (
          <div className="bubble bubble-assistant">
            <strong>Coach</strong>
            <p className="coach-loading">
              <LoaderCircle className="spin" size={16} />
              Thinking through the board.
            </p>
          </div>
        ) : null}
      </div>

      {error ? <p className="inline-error">{error.message}</p> : null}

      <form className="coach-form" onSubmit={submit}>
        <textarea
          rows={3}
          value={input}
          onChange={(event) => setInput(event.target.value)}
          placeholder="Ask the coach for a scheduling recommendation..."
        />
        <button className="primary-button" type="submit" disabled={isLoading}>
          <SendHorizontal size={16} />
          Send
        </button>
      </form>
    </div>
  );
}
