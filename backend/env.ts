import { z } from 'zod';

export const env = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    DATABASE_URL: z
      .string()
      .min(1)
      .default('postgres://postgres:postgres@localhost:5432/poddashboard'),
    AUTH_SECRET: z.string().min(1).default('dev-secret-change-me'),
    AUTH_URL: z.string().url().default('http://localhost:3000'),
    APP_URL: z.string().url().default('http://localhost:3000'),
    API_URL: z.string().url().default('http://localhost:3001'),
    PORT: z.coerce.number().int().positive().default(3001),
  })
  .parse(process.env);
