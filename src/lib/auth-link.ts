import { clearPendingMagicLinkEmail, getPendingMagicLinkEmail } from '@/lib/magic-link-state';
import { supabase } from '@/lib/supabase';

type SupportedOtpType =
  | 'signup'
  | 'invite'
  | 'magiclink'
  | 'recovery'
  | 'email_change'
  | 'email';

export type AuthParams = {
  code: string | null;
  tokenHash: string | null;
  token: string | null;
  type: string | null;
  accessToken: string | null;
  refreshToken: string | null;
  error: string | null;
  errorCode: string | null;
  errorDescription: string | null;
};

export type RouteAuthParams = Record<
  | 'code'
  | 'token_hash'
  | 'token'
  | 'type'
  | 'access_token'
  | 'refresh_token'
  | 'error'
  | 'error_code'
  | 'error_description',
  string | string[] | undefined
>;

export type CompleteAuthResult = {
  handled: boolean;
  sessionCreated: boolean;
  message: string | null;
};

function parseParamSegment(segment: string) {
  const params = new Map<string, string>();
  const decodeValue = (value: string) => decodeURIComponent(value.replace(/\+/g, ' '));

  for (const pair of segment.split('&')) {
    if (!pair) continue;
    const separatorIndex = pair.indexOf('=');
    const rawKey = separatorIndex >= 0 ? pair.slice(0, separatorIndex) : pair;
    const rawValue = separatorIndex >= 0 ? pair.slice(separatorIndex + 1) : '';
    const key = decodeValue(rawKey);
    if (!key) continue;
    params.set(key, decodeValue(rawValue));
  }

  return params;
}

export function redactSensitiveAuthUrl(value: string | null) {
  return (
    value?.replace(/(token_hash|token|access_token|refresh_token|code)=([^&#]+)/g, '$1=[redacted]') ??
    null
  );
}

export function parseAuthParamsFromUrl(rawUrl: string): AuthParams {
  const hashIndex = rawUrl.indexOf('#');
  const queryIndex = rawUrl.indexOf('?');
  const queryEnd = hashIndex >= 0 ? hashIndex : rawUrl.length;
  const query =
    queryIndex >= 0 && queryIndex < queryEnd ? rawUrl.slice(queryIndex + 1, queryEnd) : '';
  const hash = hashIndex >= 0 ? rawUrl.slice(hashIndex + 1) : '';
  const queryParams = parseParamSegment(query);
  const hashParams = parseParamSegment(hash);

  const getParam = (key: string): string | null => queryParams.get(key) ?? hashParams.get(key) ?? null;

  return {
    code: getParam('code'),
    tokenHash: getParam('token_hash'),
    token: getParam('token'),
    type: getParam('type'),
    accessToken: getParam('access_token'),
    refreshToken: getParam('refresh_token'),
    error: getParam('error'),
    errorCode: getParam('error_code'),
    errorDescription: getParam('error_description'),
  };
}

export function parseAuthParamsFromRouteParams(params: RouteAuthParams): AuthParams {
  const pick = (value: string | string[] | undefined) =>
    Array.isArray(value) ? (value[0] ?? null) : (value ?? null);

  return {
    code: pick(params.code),
    tokenHash: pick(params.token_hash),
    token: pick(params.token),
    type: pick(params.type),
    accessToken: pick(params.access_token),
    refreshToken: pick(params.refresh_token),
    error: pick(params.error),
    errorCode: pick(params.error_code),
    errorDescription: pick(params.error_description),
  };
}

export async function completeAuthFromParsed(parsed: AuthParams): Promise<CompleteAuthResult> {
  const { code, tokenHash, token, type, accessToken, refreshToken, error, errorCode, errorDescription } =
    parsed;

  if (error || errorCode || errorDescription) {
    return {
      handled: true,
      sessionCreated: false,
      message: errorDescription ?? errorCode ?? error ?? 'Unable to sign in.',
    };
  }

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      return { handled: true, sessionCreated: false, message: error.message };
    }
  } else if (type && (tokenHash || token)) {
    const otpType = type as SupportedOtpType;
    const tokenHashCandidate = tokenHash ?? token;
    if (!tokenHashCandidate) {
      return { handled: false, sessionCreated: false, message: null };
    }
    let { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHashCandidate,
      type: otpType,
    });

    if (error && token) {
      const pendingEmail = getPendingMagicLinkEmail();
      if (pendingEmail) {
        const verifyByEmail = await supabase.auth.verifyOtp({
          email: pendingEmail,
          token,
          type: otpType,
        });
        error = verifyByEmail.error;
      }
    }

    if (error) {
      return { handled: true, sessionCreated: false, message: error.message };
    }
  } else if (accessToken && refreshToken) {
    const { error } = await supabase.auth.setSession({
      access_token: accessToken,
      refresh_token: refreshToken,
    });

    if (error) {
      return { handled: true, sessionCreated: false, message: error.message };
    }
  } else {
    return { handled: false, sessionCreated: false, message: null };
  }

  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return {
      handled: true,
      sessionCreated: false,
      message: 'Sign-in link was opened, but no session was created. Request a new link.',
    };
  }

  clearPendingMagicLinkEmail();
  return { handled: true, sessionCreated: true, message: null };
}
