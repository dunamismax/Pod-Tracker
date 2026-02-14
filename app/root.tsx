import type { ReactNode } from 'react';
import {
  Form,
  Link,
  Links,
  Meta,
  Outlet,
  Scripts,
  ScrollRestoration,
  useRouteLoaderData,
  type LoaderFunctionArgs,
} from 'react-router';

import { getUserFromRequest } from './lib/session.server';
import stylesheetHref from './styles.css?url';

export function meta() {
  return [
    { title: 'Magic Pod Dashboard' },
    {
      name: 'description',
      content: 'Manage tabletop pods, events, attendance, and invites.',
    },
  ];
}

export function links() {
  return [{ rel: 'stylesheet', href: stylesheetHref }];
}

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await getUserFromRequest(request);
  return { user };
}

export function Layout({ children }: { children: ReactNode }) {
  const rootData = useRouteLoaderData<typeof loader>('root');
  const user = rootData?.user ?? null;

  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Meta />
        <Links />
      </head>
      <body>
        <header className="site-header">
          <div className="shell nav-row">
            <Link to="/" className="brand">
              Magic Pod Dashboard
            </Link>
            <div className="nav-actions">
              {user ? (
                <>
                  <span className="muted">{user.email}</span>
                  <Form method="post" action="/logout">
                    <button type="submit" className="button secondary">
                      Sign out
                    </button>
                  </Form>
                </>
              ) : (
                <Link to="/login" className="button secondary">
                  Sign in
                </Link>
              )}
            </div>
          </div>
        </header>
        <main className="shell">{children}</main>
        <ScrollRestoration />
        <Scripts />
      </body>
    </html>
  );
}

export default function App() {
  return <Outlet />;
}
