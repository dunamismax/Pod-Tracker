type ApiFetchOptions = {
  body?: Record<string, unknown>;
  method?: string;
};

function getCsrfToken(): string | null {
  const match = document.cookie.match(/(?:^|;\s*)csrf_token=([^;]+)/);
  return match?.[1] ?? null;
}

export async function apiFetch<T>(path: string, options: ApiFetchOptions = {}): Promise<T> {
  const method = options.method ?? 'GET';
  const headers: Record<string, string> = {};

  if (options.body) {
    headers['Content-Type'] = 'application/json';
  }

  const isMutating = method === 'POST' || method === 'PUT' || method === 'DELETE';
  if (isMutating) {
    const csrf = getCsrfToken();
    if (csrf) {
      headers['x-csrf-token'] = csrf;
    }
  }

  const init: RequestInit = {
    method,
    credentials: 'include',
    headers,
  };

  if (options.body) {
    init.body = JSON.stringify(options.body);
  }

  const response = await fetch(path, init);

  if (!response.ok) {
    const data = await response.json().catch(() => null);
    const error = new Error(data?.error ?? response.statusText);
    Object.assign(error, { data, status: response.status });
    throw error;
  }

  return response.json();
}
