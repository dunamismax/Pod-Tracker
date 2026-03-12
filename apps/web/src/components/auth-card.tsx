import { useNavigate } from "@tanstack/react-router";
import { LoaderCircle } from "lucide-react";
import { useState } from "react";

import { authClient } from "#/lib/auth-client";

export function AuthCard() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<"sign-in" | "sign-up">("sign-up");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, setIsPending] = useState(false);

  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setIsPending(true);
    setError(null);

    try {
      if (mode === "sign-up") {
        const result = await authClient.signUp.email({
          email,
          password,
          name,
        });

        if (result.error) {
          setError(result.error.message || "Could not create the account.");
          return;
        }
      } else {
        const result = await authClient.signIn.email({
          email,
          password,
        });

        if (result.error) {
          setError(result.error.message || "Could not sign in.");
          return;
        }
      }

      await navigate({ to: "/app" });
    } finally {
      setIsPending(false);
    }
  };

  return (
    <article className="auth-card">
      <div className="auth-switch">
        <button
          type="button"
          className={mode === "sign-up" ? "is-active" : undefined}
          onClick={() => {
            setMode("sign-up");
            setError(null);
          }}
        >
          Create account
        </button>
        <button
          type="button"
          className={mode === "sign-in" ? "is-active" : undefined}
          onClick={() => {
            setMode("sign-in");
            setError(null);
          }}
        >
          Sign in
        </button>
      </div>

      <div className="auth-copy">
        <p className="eyebrow">Private Workspace</p>
        <h1>
          {mode === "sign-up"
            ? "Start a new pod board."
            : "Return to your pod board."}
        </h1>
        <p>
          PodWatch is now an authenticated planning workspace. Every pod, count,
          and event timeline is scoped to the current account.
        </p>
      </div>

      <form className="auth-form" onSubmit={submit}>
        {mode === "sign-up" ? (
          <label className="field">
            <span>Name</span>
            <input
              autoComplete="name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Sawyer"
              required
            />
          </label>
        ) : null}

        <label className="field">
          <span>Email</span>
          <input
            autoComplete="email"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="sawyer@example.com"
            required
          />
        </label>

        <label className="field">
          <span>Password</span>
          <input
            autoComplete={
              mode === "sign-up" ? "new-password" : "current-password"
            }
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="At least 8 characters"
            minLength={8}
            required
          />
        </label>

        {error ? <p className="inline-error">{error}</p> : null}

        <button className="primary-button" type="submit" disabled={isPending}>
          {isPending ? <LoaderCircle className="spin" size={18} /> : null}
          {mode === "sign-up" ? "Create account" : "Sign in"}
        </button>
      </form>
    </article>
  );
}
