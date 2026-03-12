import { relations } from "drizzle-orm";
import {
  boolean,
  index,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

export const users = pgTable(
  "user",
  {
    id: text("id").primaryKey(),
    name: text("name").notNull(),
    email: text("email").notNull(),
    emailVerified: boolean("email_verified").notNull().default(false),
    image: text("image"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
  },
  (table) => ({
    userEmailUnique: uniqueIndex("user_email_unique").on(table.email),
  }),
);

export const sessions = pgTable(
  "session",
  {
    id: text("id").primaryKey(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    token: text("token").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    ipAddress: text("ip_address"),
    userAgent: text("user_agent"),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => ({
    sessionTokenUnique: uniqueIndex("session_token_unique").on(table.token),
    sessionUserIdIndex: index("session_user_id_idx").on(table.userId),
  }),
);

export const accounts = pgTable(
  "account",
  {
    id: text("id").primaryKey(),
    accountId: text("account_id").notNull(),
    providerId: text("provider_id").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    accessToken: text("access_token"),
    refreshToken: text("refresh_token"),
    idToken: text("id_token"),
    accessTokenExpiresAt: timestamp("access_token_expires_at", {
      withTimezone: true,
    }),
    refreshTokenExpiresAt: timestamp("refresh_token_expires_at", {
      withTimezone: true,
    }),
    scope: text("scope"),
    password: text("password"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
  },
  (table) => ({
    accountProviderUnique: uniqueIndex("account_provider_account_unique").on(
      table.providerId,
      table.accountId,
    ),
    accountUserIdIndex: index("account_user_id_idx").on(table.userId),
  }),
);

export const verifications = pgTable(
  "verification",
  {
    id: text("id").primaryKey(),
    identifier: text("identifier").notNull(),
    value: text("value").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
  },
  (table) => ({
    verificationIdentifierIndex: index("verification_identifier_idx").on(
      table.identifier,
    ),
    verificationValueUnique: uniqueIndex("verification_value_unique").on(
      table.value,
    ),
  }),
);

export const pods = pgTable(
  "pod",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: text("owner_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    nameNormalized: text("name_normalized").notNull(),
    description: text("description").notNull().default(""),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => ({
    podOwnerIndex: index("pod_owner_idx").on(table.ownerId),
    podOwnerNameUnique: uniqueIndex("pod_owner_name_normalized_unique").on(
      table.ownerId,
      table.nameNormalized,
    ),
  }),
);

export const events = pgTable(
  "event",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: text("owner_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    podId: uuid("pod_id")
      .notNull()
      .references(() => pods.id, { onDelete: "cascade" }),
    title: text("title").notNull(),
    description: text("description").notNull().default(""),
    location: text("location").notNull().default(""),
    scheduledFor: timestamp("scheduled_for", { withTimezone: true }).notNull(),
    scheduledTimezone: text("scheduled_timezone").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => ({
    eventOwnerIndex: index("event_owner_idx").on(table.ownerId),
    eventOwnerScheduledForIndex: index("event_owner_scheduled_for_idx").on(
      table.ownerId,
      table.scheduledFor,
    ),
    eventPodIndex: index("event_pod_idx").on(table.podId),
  }),
);

export const userRelations = relations(users, ({ many }) => ({
  pods: many(pods),
  sessions: many(sessions),
  accounts: many(accounts),
}));

export const podRelations = relations(pods, ({ one, many }) => ({
  owner: one(users, {
    fields: [pods.ownerId],
    references: [users.id],
  }),
  events: many(events),
}));

export const eventRelations = relations(events, ({ one }) => ({
  owner: one(users, {
    fields: [events.ownerId],
    references: [users.id],
  }),
  pod: one(pods, {
    fields: [events.podId],
    references: [pods.id],
  }),
}));

export const sessionRelations = relations(sessions, ({ one }) => ({
  user: one(users, {
    fields: [sessions.userId],
    references: [users.id],
  }),
}));

export const accountRelations = relations(accounts, ({ one }) => ({
  user: one(users, {
    fields: [accounts.userId],
    references: [users.id],
  }),
}));
