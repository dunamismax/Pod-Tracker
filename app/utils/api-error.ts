export function getApiErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error) {
    const data = Reflect.get(error, 'data');

    if (data && typeof data === 'object') {
      const message = Reflect.get(data, 'error');
      if (typeof message === 'string' && message.length > 0) {
        return message;
      }
    }

    if (error.message.length > 0) {
      return error.message;
    }
  }

  return fallback;
}
