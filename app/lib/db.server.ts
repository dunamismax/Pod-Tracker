import { Pool } from 'pg';

import { env } from './env.server';

const globalForDb = globalThis as typeof globalThis & {
  __podDashboardDbPool?: Pool;
};

export const db =
  globalForDb.__podDashboardDbPool ??
  new Pool({
    connectionString: env.DATABASE_URL,
    max: 10,
  });

if (env.NODE_ENV !== 'production') {
  globalForDb.__podDashboardDbPool = db;
}
