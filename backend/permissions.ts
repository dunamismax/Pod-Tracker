import { and, eq } from 'drizzle-orm';
import { permissions, rolePermissions, roles, userRoles } from '../db/schema';
import { db } from './db';

export const ROLE_MEMBER = 'member';
export const ROLE_ADMIN = 'admin';

export const MEMBER_PERMISSIONS = [
  'dashboard.view',
  'pods.create',
  'api.access',
  'api.pods.create',
];

export const ADMIN_PERMISSIONS = [
  ...MEMBER_PERMISSIONS,
  'monitoring.pulse.view',
  'monitoring.telescope.view',
];

export async function userHasPermission(userId: number, permissionName: string): Promise<boolean> {
  const permission = await db
    .select({ id: permissions.id })
    .from(permissions)
    .where(eq(permissions.name, permissionName))
    .limit(1);

  if (!permission[0]) {
    return false;
  }

  const membership = await db
    .select({ roleId: userRoles.roleId })
    .from(userRoles)
    .innerJoin(
      rolePermissions,
      and(
        eq(rolePermissions.roleId, userRoles.roleId),
        eq(rolePermissions.permissionId, permission[0].id),
      ),
    )
    .where(and(eq(userRoles.userId, userId), eq(userRoles.active, true)))
    .limit(1);

  return membership.length > 0;
}

export async function ensureAccessControlBootstrap(): Promise<void> {
  for (const permissionName of ADMIN_PERMISSIONS) {
    await db
      .insert(permissions)
      .values({ name: permissionName })
      .onConflictDoUpdate({ target: permissions.name, set: { name: permissionName } });
  }

  const [memberRole] = await db
    .insert(roles)
    .values({ name: ROLE_MEMBER })
    .onConflictDoUpdate({ target: roles.name, set: { name: ROLE_MEMBER } })
    .returning({ id: roles.id });

  const [adminRole] = await db
    .insert(roles)
    .values({ name: ROLE_ADMIN })
    .onConflictDoUpdate({ target: roles.name, set: { name: ROLE_ADMIN } })
    .returning({ id: roles.id });

  if (!memberRole || !adminRole) {
    throw new Error('Access control bootstrap failed.');
  }

  const allPermissions = await db.select().from(permissions);
  const memberPermissionIds = allPermissions
    .filter((permission) => MEMBER_PERMISSIONS.includes(permission.name))
    .map((permission) => permission.id);
  const adminPermissionIds = allPermissions.map((permission) => permission.id);

  for (const permissionId of memberPermissionIds) {
    await db
      .insert(rolePermissions)
      .values({ roleId: memberRole.id, permissionId })
      .onConflictDoNothing();
  }

  for (const permissionId of adminPermissionIds) {
    await db
      .insert(rolePermissions)
      .values({ roleId: adminRole.id, permissionId })
      .onConflictDoNothing();
  }
}
