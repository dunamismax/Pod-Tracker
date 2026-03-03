import { type FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { Button } from '~/components/ui/button';
import { Card, CardBody } from '~/components/ui/card';
import { Input } from '~/components/ui/input';
import { authClient } from '~/lib/auth-client';

function validateEmail(value: string): string | null {
  if (!value.trim()) return 'Email is required.';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return 'Enter a valid email address.';
  return null;
}

function validatePassword(value: string): string | null {
  if (!value) return 'Password is required.';
  if (value.length < 6) return 'Password must be at least 6 characters.';
  return null;
}

export default function LoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [touched, setTouched] = useState<Record<string, boolean>>({});

  const emailError = touched.email ? validateEmail(email) : null;
  const passwordError = touched.password ? validatePassword(password) : null;
  const hasFieldErrors = !!validateEmail(email) || !!validatePassword(password);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setTouched({ email: true, password: true });
    setError(null);

    if (hasFieldErrors) return;

    setPending(true);

    try {
      const result = await authClient.signIn.email({ email, password });
      if (result.error) {
        setError(result.error.message ?? 'Invalid credentials.');
      } else {
        navigate('/dashboard');
      }
    } catch {
      setError('Invalid credentials.');
    } finally {
      setPending(false);
    }
  }

  return (
    <main className="flex min-h-[calc(100vh-3rem)] items-center justify-center">
      <Card className="w-full max-w-md shadow-2xl shadow-cyan-950/30">
        <CardBody className="space-y-6 p-8 sm:p-9">
          <div className="space-y-3">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-cyan-200/80">
              Auth
            </p>
            <div className="space-y-2">
              <h1 className="text-3xl font-semibold text-white">Sign in</h1>
              <p className="text-sm text-slate-300">
                Get back to your pods, your events, and whatever chaos you scheduled on purpose.
              </p>
            </div>
          </div>

          <form className="space-y-4" onSubmit={handleSubmit}>
            <div className="space-y-2">
              <label className="text-sm text-slate-200" htmlFor="email">
                Email
              </label>
              <Input
                id="email"
                type="email"
                placeholder="test@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, email: true }))}
                aria-invalid={emailError ? true : undefined}
                aria-describedby={emailError ? 'email-error' : undefined}
              />
              {emailError && (
                <p id="email-error" className="text-xs text-rose-300">
                  {emailError}
                </p>
              )}
            </div>

            <div className="space-y-2">
              <label className="text-sm text-slate-200" htmlFor="password">
                Password
              </label>
              <Input
                id="password"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, password: true }))}
                aria-invalid={passwordError ? true : undefined}
                aria-describedby={passwordError ? 'password-error' : undefined}
              />
              {passwordError && (
                <p id="password-error" className="text-xs text-rose-300">
                  {passwordError}
                </p>
              )}
            </div>

            {error && (
              <p
                role="alert"
                className="rounded-2xl border border-rose-400/35 bg-rose-950/40 px-3 py-2 text-sm text-rose-200"
              >
                {error}
              </p>
            )}

            <Button className="w-full justify-center" size="xl" loading={pending} type="submit">
              Sign in
            </Button>
          </form>

          {import.meta.env.DEV && (
            <div className="rounded-2xl border border-white/10 bg-slate-950/30 px-4 py-3 text-sm text-slate-300">
              Seeded admin for local validation:{' '}
              <span className="font-medium text-white">test@example.com</span> /{' '}
              <span className="font-medium text-white">password</span>
            </div>
          )}

          <p className="text-sm text-slate-300">
            Need an account?{' '}
            <Link
              className="font-medium text-cyan-300 transition hover:text-cyan-200"
              to="/register"
            >
              Register
            </Link>
          </p>
        </CardBody>
      </Card>
    </main>
  );
}
