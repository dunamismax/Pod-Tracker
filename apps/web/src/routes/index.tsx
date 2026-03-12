import { createFileRoute, Link, redirect } from "@tanstack/react-router";

import { getViewer } from "#/lib/server-fns";

export const Route = createFileRoute("/")({
  beforeLoad: async () => {
    const viewer = await getViewer();

    if (viewer) {
      throw redirect({ to: "/app" });
    }
  },
  component: LandingPage,
});

function LandingPage() {
  return (
    <main className="landing-shell">
      <section className="landing-hero">
        <p className="eyebrow">Full Rewrite</p>
        <h1>
          PodWatch has been rebuilt as a typed, authenticated planning board.
        </h1>
        <p className="lede">
          The original Django dashboard is now archived. The active app runs on
          Bun, TanStack Start, Effect, Better Auth, and Drizzle against
          PostgreSQL.
        </p>

        <div className="landing-actions">
          <Link className="primary-button" to="/login">
            Enter the workspace
          </Link>
          <a className="ghost-button" href="#stack">
            View the stack
          </a>
        </div>
      </section>

      <section className="landing-grid" id="stack">
        <article className="landing-card">
          <h2>Typed end to end</h2>
          <p>
            Effect Schema contracts shape the inputs and the domain layer before
            anything reaches the database.
          </p>
        </article>
        <article className="landing-card">
          <h2>Real sessions</h2>
          <p>
            Better Auth scopes every pod board to an account instead of exposing
            open write endpoints.
          </p>
        </article>
        <article className="landing-card">
          <h2>Postgres-native data</h2>
          <p>
            Pods and events now sit on PostgreSQL with Drizzle models and
            deployable schema management.
          </p>
        </article>
      </section>
    </main>
  );
}
