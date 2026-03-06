const configuredApiUrl = import.meta.env.VITE_API_URL?.trim() ?? '';

export const apiBaseUrl = configuredApiUrl.replace(/\/$/, '');

export function toApiUrl(path: string): string {
  if (/^https?:\/\//.test(path)) {
    return path;
  }

  return apiBaseUrl ? `${apiBaseUrl}${path}` : path;
}
