import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";
import { Pool } from "pg";

import * as schema from "./schema";

export type PodwatchDatabase = NodePgDatabase<typeof schema>;

let pool: Pool | undefined;
let database: PodwatchDatabase | undefined;

export const createDatabase = (connectionString: string) => {
  const newPool = new Pool({ connectionString });

  return drizzle(newPool, { schema });
};

export const getDatabase = () => {
  if (database) {
    return database;
  }

  const connectionString = process.env.DATABASE_URL;

  if (!connectionString) {
    throw new Error("DATABASE_URL is required.");
  }

  pool = new Pool({ connectionString });
  database = drizzle(pool, { schema });

  return database;
};

export const closeDatabase = async () => {
  await pool?.end();
  pool = undefined;
  database = undefined;
};
