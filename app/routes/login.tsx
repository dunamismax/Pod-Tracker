import { Form, Link, redirect, useActionData, type ActionFunctionArgs, type LoaderFunctionArgs } from 'react-router';

import { issueEmailOtp } from '../lib/auth.server';
import { getUserFromRequest } from '../lib/session.server';
import { loginFormSchema } from '../lib/validation';

type ActionData = {
  error?: string;
};

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await getUserFromRequest(request);
  if (user) {
    throw redirect('/');
  }
  return null;
}

export async function action({ request }: ActionFunctionArgs) {
  const formData = await request.formData();

  const parseResult = loginFormSchema.safeParse({
    email: formData.get('email'),
  });

  if (!parseResult.success) {
    return {
      error: parseResult.error.issues[0]?.message ?? 'Invalid email.',
    } satisfies ActionData;
  }

  await issueEmailOtp(parseResult.data.email);
  throw redirect(`/verify?email=${encodeURIComponent(parseResult.data.email)}`);
}

export default function LoginRoute() {
  const actionData = useActionData<ActionData>();

  return (
    <section className="panel auth-panel">
      <h1>Sign in with email OTP</h1>
      <p className="muted">Enter your email and we will send a one-time code.</p>
      <Form method="post" className="stack">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" autoComplete="email" required />
        {actionData?.error ? <p className="error">{actionData.error}</p> : null}
        <button type="submit" className="button">
          Send code
        </button>
      </Form>
      <p className="muted">
        Already got a code? <Link to="/verify">Verify it here</Link>.
      </p>
    </section>
  );
}
