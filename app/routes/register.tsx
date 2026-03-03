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

function validateConfirmation(password: string, confirmation: string): string | null {
  if (!confirmation) return 'Please confirm your password.';
  if (password !== confirmation) return 'Passwords do not match.';
  return null;
}

export default function RegisterPage() {
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [passwordConfirmation, setPasswordConfirmation] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [touched, setTouched] = useState<Record<string, boolean>>({});

  const emailError = touched.email ? validateEmail(email) : null;
  const passwordError = touched.password ? validatePassword(password) : null;
  const confirmError = touched.passwordConfirmation
    ? validateConfirmation(password, passwordConfirmation)
    : null;
  const hasFieldErrors =
    !!validateEmail(email) ||
    !!validatePassword(password) ||
    !!validateConfirmation(password, passwordConfirmation);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setTouched({ email: true, password: true, passwordConfirmation: true });
    setError(null);

    if (hasFieldErrors) return;

    setPending(true);

    try {
      const result = await authClient.signUp.email({
        name: name || email,
        email,
        password,
      });
      if (result.error) {
        setError(result.error.message ?? 'Registration failed.');
      } else {
        navigate('/dashboard');
      }
    } catch {
      setError('Registration failed.');
    } finally {
      setPending(false);
    }
  }

  return (
    <main className="flex min-h-[calc(100vh-3rem)] items-center justify-center">
      <Card className="w-full max-w-xl shadow-2xl shadow-amber-950/30">
        <CardBody className="space-y-6 p-8 sm:p-9">
          <div className="space-y-3">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-amber-200/85">
              New Crew
            </p>
            <div className="space-y-2">
              <h1 className="text-3xl font-semibold text-white">Create account</h1>
              <p className="text-sm text-slate-300">
                Join the dashboard, claim your seat, and keep the pod list from becoming folklore.
              </p>
            </div>
          </div>

          <form className="grid gap-4 sm:grid-cols-2" onSubmit={handleSubmit}>
            <div className="space-y-2 sm:col-span-2">
              <label className="text-sm text-slate-200" htmlFor="name">
                Name
              </label>
              <Input
                id="name"
                placeholder="Test User"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>

            <div className="space-y-2 sm:col-span-2">
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

            <div className="space-y-2">
              <label className="text-sm text-slate-200" htmlFor="passwordConfirmation">
                Confirm password
              </label>
              <Input
                id="passwordConfirmation"
                type="password"
                value={passwordConfirmation}
                onChange={(e) => setPasswordConfirmation(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, passwordConfirmation: true }))}
                aria-invalid={confirmError ? true : undefined}
                aria-describedby={confirmError ? 'confirm-error' : undefined}
              />
              {confirmError && (
                <p id="confirm-error" className="text-xs text-rose-300">
                  {confirmError}
                </p>
              )}
            </div>

            {error && (
              <p
                role="alert"
                className="rounded-2xl border border-rose-400/35 bg-rose-950/40 px-3 py-2 text-sm text-rose-200 sm:col-span-2"
              >
                {error}
              </p>
            )}

            <div className="sm:col-span-2">
              <Button className="w-full justify-center" size="xl" loading={pending} type="submit">
                Create account
              </Button>
            </div>
          </form>

          <p className="text-sm text-slate-300">
            Already have an account?{' '}
            <Link className="font-medium text-cyan-300 transition hover:text-cyan-200" to="/login">
              Sign in
            </Link>
          </p>
        </CardBody>
      </Card>
    </main>
  );
}
