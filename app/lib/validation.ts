import { z } from 'zod';

export const emailSchema = z.string().trim().toLowerCase().email('Enter a valid email address.');

export const otpCodeSchema = z
  .string()
  .trim()
  .regex(/^\d{6}$/, 'Enter the 6-digit code from your email.');

export const loginFormSchema = z.object({
  email: emailSchema,
});

export const verifyOtpFormSchema = z.object({
  email: emailSchema,
  code: otpCodeSchema,
});

export const createPodSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, 'Pod name must be at least 2 characters.')
    .max(120, 'Pod name must be 120 characters or fewer.'),
  description: z
    .string()
    .trim()
    .max(500, 'Description must be 500 characters or fewer.')
    .optional()
    .or(z.literal(''))
    .transform((value) => {
      if (!value) {
        return null;
      }
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }),
});
