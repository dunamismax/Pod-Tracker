import { db } from './db.server';
import { generateOtpCode, generateSessionToken, hashWithSecret } from './crypto.server';
import { sendOtpEmail } from './email.server';

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function otpHash(email: string, code: string): string {
  return hashWithSecret(`${normalizeEmail(email)}:${code}`);
}

export async function issueEmailOtp(email: string): Promise<void> {
  const normalizedEmail = normalizeEmail(email);
  const code = generateOtpCode();
  const codeHash = otpHash(normalizedEmail, code);

  await db.query(
    `
      delete from otp_codes
      where email = $1
         or expires_at < now()
         or consumed_at is not null
    `,
    [normalizedEmail]
  );

  await db.query(
    `
      insert into otp_codes (email, code_hash, expires_at)
      values ($1, $2, now() + interval '10 minutes')
    `,
    [normalizedEmail, codeHash]
  );

  await sendOtpEmail(normalizedEmail, code);
}

export async function verifyEmailOtp(email: string, code: string): Promise<string | null> {
  const normalizedEmail = normalizeEmail(email);
  const codeHash = otpHash(normalizedEmail, code);
  const sessionToken = generateSessionToken();
  const sessionTokenHash = hashWithSecret(sessionToken);
  const client = await db.connect();

  try {
    await client.query('begin');

    const otpResult = await client.query<{ id: number }>(
      `
        select id
        from otp_codes
        where email = $1
          and code_hash = $2
          and consumed_at is null
          and expires_at > now()
        order by created_at desc
        limit 1
        for update
      `,
      [normalizedEmail, codeHash]
    );

    const otpId = otpResult.rows[0]?.id;
    if (!otpId) {
      await client.query('rollback');
      return null;
    }

    await client.query(
      `
        update otp_codes
        set consumed_at = now()
        where id = $1
      `,
      [otpId]
    );

    const userResult = await client.query<{ id: number }>(
      `
        insert into users (email)
        values ($1)
        on conflict (email) do update
        set email = excluded.email
        returning id
      `,
      [normalizedEmail]
    );

    const userId = userResult.rows[0].id;

    await client.query(
      `
        insert into sessions (token_hash, user_id, expires_at)
        values ($1, $2, now() + interval '14 days')
      `,
      [sessionTokenHash, userId]
    );

    await client.query('commit');
    return sessionToken;
  } catch (error) {
    await client.query('rollback');
    throw error;
  } finally {
    client.release();
  }
}
