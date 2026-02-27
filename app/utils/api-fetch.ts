import { $fetch } from 'ofetch';
import { useRequestHeaders, useRuntimeConfig } from '#imports';

type ApiFetchOptions = {
  body?: BodyInit | Record<string, unknown> | null;
  credentials?: RequestCredentials;
  headers?: HeadersInit;
  method?: string;
  query?: Record<string, string | number | boolean | null | undefined>;
};

function mergeHeaders(baseHeaders?: HeadersInit, extraHeaders?: HeadersInit): Headers {
  const headers = new Headers(baseHeaders);

  if (extraHeaders) {
    for (const [key, value] of new Headers(extraHeaders).entries()) {
      headers.set(key, value);
    }
  }

  return headers;
}

export function apiFetch<T>(path: string, options: ApiFetchOptions = {}) {
  if (import.meta.server) {
    const runtimeConfig = useRuntimeConfig();

    return $fetch<T>(`${runtimeConfig.apiBaseUrl}${path}`, {
      ...options,
      headers: mergeHeaders(useRequestHeaders(['cookie']), options.headers),
    });
  }

  return $fetch<T>(path, {
    credentials: 'include',
    ...options,
  });
}
