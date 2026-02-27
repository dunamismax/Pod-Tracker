import { migrate } from 'drizzle-orm/node-postgres/migrator';

import { db, pool } from '../backend/db';

async function run() {
  await migrate(db, { migrationsFolder: './db/migrations' });
}

run()
  .then(() => {
    console.log('Migrations completed.');
  })
  .catch((error) => {
    console.error('Migration failed.');
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
