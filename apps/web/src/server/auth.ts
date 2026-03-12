import {
  accounts,
  getDatabase,
  sessions,
  users,
  verifications,
} from "@podwatch/db";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { tanstackStartCookies } from "better-auth/tanstack-start";

import { ensureServerBooted } from "./bootstrap";

ensureServerBooted();

const authUrl = process.env.BETTER_AUTH_URL || "http://127.0.0.1:3000";
const authSecret = process.env.BETTER_AUTH_SECRET;

if (!authSecret) {
  throw new Error("BETTER_AUTH_SECRET is required.");
}

export const auth = betterAuth({
  appName: "PodWatch",
  secret: authSecret,
  baseURL: authUrl,
  trustedOrigins: [authUrl],
  database: drizzleAdapter(getDatabase(), {
    provider: "pg",
    schema: {
      user: users,
      session: sessions,
      account: accounts,
      verification: verifications,
    },
  }),
  emailAndPassword: {
    enabled: true,
    autoSignIn: true,
  },
  plugins: [tanstackStartCookies()],
});
