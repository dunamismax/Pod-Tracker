import nodemailer from 'nodemailer';

import { env } from './env.server';

const transporter = nodemailer.createTransport({
  host: env.SMTP_HOST,
  port: env.SMTP_PORT,
  secure: env.SMTP_SECURE,
  auth: env.SMTP_USER
    ? {
        user: env.SMTP_USER,
        pass: env.SMTP_PASS ?? '',
      }
    : undefined,
});

export async function sendOtpEmail(email: string, code: string): Promise<void> {
  await transporter.sendMail({
    from: env.SMTP_FROM,
    to: email,
    subject: 'Your Magic Pod Dashboard sign-in code',
    text: `Your sign-in code is ${code}. It expires in 10 minutes.`,
    html: `<p>Your sign-in code is <strong>${code}</strong>.</p><p>It expires in 10 minutes.</p>`,
  });
}
