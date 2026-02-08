import { z } from 'zod';

const envSchema = z.object({
  VITE_SUPABASE_URL: z.string().url(),
  VITE_SUPABASE_ANON_KEY: z.string().min(1),
});

const candidateEnv = {
  VITE_SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL,
  VITE_SUPABASE_ANON_KEY: import.meta.env.VITE_SUPABASE_ANON_KEY,
};

const parsed = envSchema.safeParse(candidateEnv);

if (!parsed.success) {
  const missing = parsed.error.issues
    .map((issue) => issue.path.join('.'))
    .filter(Boolean)
    .join(', ');

  throw new Error(
    [
      'Missing or invalid environment configuration.',
      `Set these variables in .env: ${missing}`,
      'Example: copy .env.example to .env and fill in your Supabase project URL and anon key.',
    ].join(' ')
  );
}

export const env = parsed.data;
