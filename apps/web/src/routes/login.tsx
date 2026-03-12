import { createFileRoute, redirect } from "@tanstack/react-router";

import { AuthCard } from "#/components/auth-card";
import { getViewer } from "#/lib/server-fns";

export const Route = createFileRoute("/login")({
  beforeLoad: async () => {
    const viewer = await getViewer();

    if (viewer) {
      throw redirect({ to: "/app" });
    }
  },
  component: LoginPage,
});

function LoginPage() {
  return (
    <main className="auth-shell">
      <AuthCard />
    </main>
  );
}
