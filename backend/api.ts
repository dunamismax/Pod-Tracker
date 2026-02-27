import { compare, hash } from 'bcryptjs';
import { and, desc, eq, gte, sql } from 'drizzle-orm';
import { z } from 'zod';
import { events, podMembers, pods, roles, userRoles, users } from '../db/schema';
import { db } from './db';
import { json } from './http';
import { userHasPermission } from './permissions';
import {
  appendSessionCookie,
  clearSessionCookies,
  createSession,
  destroySession,
  resolveSessionUser,
} from './session';

const createPodSchema = z.object({
  name: z.string().trim().min(2, 'Pod name must be at least 2 characters.').max(120),
  description: z.string().trim().max(500).optional().nullable(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required.'),
});

const registerSchema = z
  .object({
    name: z.string().trim().max(255).optional().nullable(),
    email: z.string().email(),
    password: z.string().min(8, 'Password must be at least 8 characters.'),
    passwordConfirmation: z.string(),
  })
  .refine((value) => value.password === value.passwordConfirmation, {
    message: 'Password confirmation does not match.',
    path: ['passwordConfirmation'],
  });

async function requirePermission(request: Request, permission: string) {
  const user = await resolveSessionUser(request);

  if (!user) {
    return { error: json({ error: 'Unauthorized' }, 401) };
  }

  const allowed = await userHasPermission(user.id, permission);

  if (!allowed) {
    return { error: json({ error: 'Forbidden' }, 403) };
  }

  return { user };
}

async function parseJson(
  request: Request,
): Promise<{ ok: true; data: unknown } | { ok: false; error: Response }> {
  try {
    return { ok: true, data: await request.json() };
  } catch {
    return {
      ok: false,
      error: json({ error: 'Request body must be valid JSON.' }, 400),
    };
  }
}

export async function handleSession(request: Request): Promise<Response> {
  const user = await resolveSessionUser(request);

  return json({
    authenticated: Boolean(user),
    user,
  });
}

export async function handleLogin(request: Request): Promise<Response> {
  const parsedBody = await parseJson(request);
  if (!parsedBody.ok) {
    return parsedBody.error;
  }

  const payload = loginSchema.safeParse(parsedBody.data);
  if (!payload.success) {
    return json({ error: payload.error.issues[0]?.message ?? 'Invalid payload.' }, 400);
  }

  const user = await db
    .select({
      id: users.id,
      email: users.email,
      name: users.name,
      passwordHash: users.passwordHash,
    })
    .from(users)
    .where(eq(users.email, payload.data.email))
    .limit(1);

  if (!user[0]) {
    return json({ error: 'Invalid credentials.' }, 401);
  }

  const validPassword = await compare(payload.data.password, user[0].passwordHash);
  if (!validPassword) {
    return json({ error: 'Invalid credentials.' }, 401);
  }

  const { expires, sessionToken } = await createSession(user[0].id);
  const headers = new Headers();
  appendSessionCookie(headers, sessionToken, expires);

  return json(
    {
      status: 'ok',
      user: {
        email: user[0].email,
        id: user[0].id,
        name: user[0].name,
      },
    },
    200,
    { headers },
  );
}

export async function handleLogout(request: Request): Promise<Response> {
  await destroySession(request);

  const headers = new Headers();
  clearSessionCookies(headers);

  return json({ status: 'ok' }, 200, { headers });
}

export async function handleRegister(request: Request): Promise<Response> {
  const parsedBody = await parseJson(request);
  if (!parsedBody.ok) {
    return parsedBody.error;
  }

  const payload = registerSchema.safeParse(parsedBody.data);
  if (!payload.success) {
    return json({ error: payload.error.issues[0]?.message ?? 'Invalid payload.' }, 400);
  }

  const existing = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.email, payload.data.email))
    .limit(1);

  if (existing[0]) {
    return json({ error: 'Email already exists.' }, 400);
  }

  const [memberRole] = await db
    .select({ id: roles.id })
    .from(roles)
    .where(eq(roles.name, 'member'))
    .limit(1);

  if (!memberRole) {
    return json({ error: 'Role configuration missing.' }, 500);
  }

  const passwordHash = await hash(payload.data.password, 12);

  const [createdUser] = await db
    .insert(users)
    .values({
      name: payload.data.name ?? null,
      email: payload.data.email,
      passwordHash,
    })
    .returning({ id: users.id });

  if (!createdUser) {
    return json({ error: 'User creation failed.' }, 500);
  }

  await db
    .insert(userRoles)
    .values({ userId: createdUser.id, roleId: memberRole.id })
    .onConflictDoNothing();

  return json({ status: 'ok' }, 201);
}

export async function handlePodsIndex(request: Request): Promise<Response> {
  const access = await requirePermission(request, 'api.access');
  if (access.error) {
    return access.error;
  }

  const records = await db
    .select({
      id: pods.id,
      name: pods.name,
      description: pods.description,
      role: podMembers.role,
    })
    .from(podMembers)
    .innerJoin(pods, eq(pods.id, podMembers.podId))
    .where(eq(podMembers.userId, access.user.id))
    .orderBy(desc(pods.createdAt));

  return json({ pods: records });
}

export async function handlePodsCreate(request: Request): Promise<Response> {
  const access = await requirePermission(request, 'api.access');
  if (access.error) {
    return access.error;
  }

  const canCreatePod = await userHasPermission(access.user.id, 'api.pods.create');
  if (!canCreatePod) {
    return json({ error: 'Forbidden' }, 403);
  }

  const parsedBody = await parseJson(request);
  if (!parsedBody.ok) {
    return parsedBody.error;
  }

  const payload = createPodSchema.safeParse(parsedBody.data);
  if (!payload.success) {
    return json({ error: payload.error.issues[0]?.message ?? 'Invalid payload.' }, 400);
  }

  const description = payload.data.description?.trim() || null;

  const [pod] = await db.transaction(async (tx) => {
    const [createdPod] = await tx
      .insert(pods)
      .values({
        name: payload.data.name.trim(),
        description,
        ownerId: access.user.id,
      })
      .returning({
        id: pods.id,
        name: pods.name,
        description: pods.description,
      });

    if (!createdPod) {
      throw new Error('Pod creation failed.');
    }

    await tx.insert(podMembers).values({
      podId: createdPod.id,
      userId: access.user.id,
      role: 'owner',
    });

    return [createdPod];
  });

  return json(
    {
      pod: {
        ...pod,
        role: 'owner',
      },
    },
    201,
  );
}

export async function handleEventsIndex(request: Request): Promise<Response> {
  const access = await requirePermission(request, 'api.access');
  if (access.error) {
    return access.error;
  }

  const records = await db
    .select({
      id: events.id,
      podName: pods.name,
      title: events.title,
      location: events.location,
      scheduledFor: events.scheduledFor,
    })
    .from(events)
    .innerJoin(pods, eq(pods.id, events.podId))
    .innerJoin(
      podMembers,
      and(eq(podMembers.podId, events.podId), eq(podMembers.userId, access.user.id)),
    )
    .where(gte(events.scheduledFor, sql`NOW() - INTERVAL '1 day'`))
    .orderBy(events.scheduledFor)
    .limit(20);

  return json({
    events: records.map((event) => ({
      ...event,
      scheduledFor: event.scheduledFor?.toISOString() ?? null,
    })),
  });
}
