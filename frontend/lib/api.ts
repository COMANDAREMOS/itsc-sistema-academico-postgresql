export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message); this.name = 'ApiError'; }
}

export async function api<T = any>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  if (options.body && !(options.body instanceof FormData)) headers.set('Content-Type', 'application/json');
  if (options.method && !['GET', 'HEAD'].includes(options.method.toUpperCase())) headers.set('X-Requested-With', 'ITSC');
  const response = await fetch(`/api${path}`, { ...options, headers, credentials: 'same-origin', cache: 'no-store' });
  const text = await response.text();
  let body: any;
  try { body = text ? JSON.parse(text) : {}; } catch { body = { message: 'El servidor no pudo completar la solicitud.' }; }
  if (!response.ok) {
    if (response.status === 401 && path !== '/auth/login' && typeof window !== 'undefined') window.dispatchEvent(new Event('itsc-session-expired'));
    const message = Array.isArray(body.message) ? body.message.join('. ') : body.message || body.error || 'No se pudo completar la operación.';
    throw new ApiError(message, response.status);
  }
  return body as T;
}

export function params(values: Record<string, unknown>): string {
  const query = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => { if (value !== undefined && value !== null && value !== '') query.set(key, String(value)); });
  return query.toString();
}
