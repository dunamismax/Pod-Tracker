import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { Pool } from 'pg';
import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
});

const envResult = envSchema.safeParse(process.env);
if (!envResult.success) {
  throw new Error(envResult.error.issues.map((issue) => issue.message).join(', '));
}

const pool = new Pool({
  connectionString: envResult.data.DATABASE_URL,
});

const sqlPath = path.resolve(process.cwd(), 'scripts/postgres-setup.sql');
const sql = await readFile(sqlPath, 'utf8');

try {
  await pool.query(sql);
  console.warn(`Database schema applied from ${sqlPath}`);
} finally {
  await pool.end();
}
