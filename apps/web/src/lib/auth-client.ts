import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient({
  baseURL:
    typeof window === "undefined"
      ? "http://127.0.0.1:3000"
      : window.location.origin,
});
