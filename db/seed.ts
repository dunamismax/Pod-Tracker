import { hash } from 'bcryptjs';
import { eq } from 'drizzle-orm';
import { db, pool } from '../backend/db';
import { ensureAccessControlBootstrap, ROLE_ADMIN } from '../backend/permissions';
import { roles, userRoles, users } from './schema';

async function seed() {
  await ensureAccessControlBootstrap();

  const [adminRole] = await db
    .select({ id: roles.id })
    .from(roles)
    .where(eq(roles.name, ROLE_ADMIN))
    .limit(1);

  if (!adminRole) {
    throw new Error('Admin role bootstrap failed.');
  }

  const existingUser = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.email, 'test@example.com'))
    .limit(1);

  const passwordHash = await hash('password', 12);

  const userId =
    existingUser[0]?.id ??
    (
      await db
        .insert(users)
        .values({
          email: 'test@example.com',
          name: 'Test User',
          passwordHash,
        })
        .returning({ id: users.id })
    )[0]?.id;

  if (!userId) {
    throw new Error('User seed failed.');
  }

  if (existingUser[0]) {
    await db.update(users).set({ passwordHash }).where(eq(users.id, userId));
  }

  await db.insert(userRoles).values({ userId, roleId: adminRole.id }).onConflictDoNothing();

  console.log('Seed complete: test@example.com / password (admin)');
}

seed()
  .catch((error) => {
    console.error('Seed failed.');
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
