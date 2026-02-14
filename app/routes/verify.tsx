import {
  Form,
  Link,
  redirect,
  useActionData,
  useLoaderData,
  type ActionFunctionArgs,
  type LoaderFunctionArgs,
} from 'react-router';

import { verifyEmailOtp } from '../lib/auth.server';
import { commitSessionCookie, getUserFromRequest } from '../lib/session.server';
import { verifyOtpFormSchema } from '../lib/validation';

type ActionData = {
  error?: string;
};

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await getUserFromRequest(request);
  if (user) {
    throw redirect('/');
  }

  const url = new URL(request.url);
  const email = url.searchParams.get('email') ?? '';

  return { email };
}

export async function action({ request }: ActionFunctionArgs) {
  const formData = await request.formData();

  const parseResult = verifyOtpFormSchema.safeParse({
    email: formData.get('email'),
    code: formData.get('code'),
  });

  if (!parseResult.success) {
    return {
      error: parseResult.error.issues[0]?.message ?? 'Invalid code.',
    } satisfies ActionData;
  }

  const sessionToken = await verifyEmailOtp(parseResult.data.email, parseResult.data.code);

  if (!sessionToken) {
    return {
      error: 'Invalid or expired code.',
    } satisfies ActionData;
  }

  throw redirect('/', {
    headers: {
      'Set-Cookie': await commitSessionCookie(sessionToken),
    },
  });
}

export default function VerifyRoute() {
  const { email } = useLoaderData<typeof loader>();
  const actionData = useActionData<ActionData>();

  return (
    <section className="panel auth-panel">
      <h1>Verify your sign-in code</h1>
      <p className="muted">Enter the 6-digit code we emailed to you.</p>
      <Form method="post" className="stack">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" defaultValue={email} autoComplete="email" required />

        <label htmlFor="code">Code</label>
        <input id="code" name="code" type="text" inputMode="numeric" pattern="\d{6}" maxLength={6} required />

        {actionData?.error ? <p className="error">{actionData.error}</p> : null}
        <button type="submit" className="button">
          Sign in
        </button>
      </Form>
      <p className="muted">
        Need another code? <Link to="/login">Request a new one</Link>.
      </p>
    </section>
  );
}
