import { createHash, randomBytes, randomInt } from 'node:crypto';

import { env } from './env.server';

export function hashWithSecret(value: string): string {
  return createHash('sha256').update(`${value}:${env.SESSION_SECRET}`).digest('hex');
}

export function generateSessionToken(): string {
  return randomBytes(32).toString('hex');
}

export function generateOtpCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}
