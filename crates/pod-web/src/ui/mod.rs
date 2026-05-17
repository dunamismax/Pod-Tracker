use leptos::prelude::*;

pub fn render_home() -> String {
    view! {
        <AppShell title="Pod Tracker">
            <main class="shell">
                <section class="hero">
                    <p class="eyebrow">"Commander night operations"</p>
                    <h1>"Pod Tracker"</h1>
                    <p>
                        "Plan events, collect RSVPs, form fair pods, log games, and keep the playgroup meta visible."
                    </p>
                    <nav class="actions" aria-label="Primary">
                        <a href="/home">"Dashboard"</a>
                        <a href="/signup">"Sign up"</a>
                        <a href="/status">"Status"</a>
                    </nav>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_status(database_configured: bool, smtp_configured: bool) -> String {
    let database = if database_configured {
        "configured"
    } else {
        "missing"
    };
    let email = if smtp_configured {
        "configured"
    } else {
        "missing"
    };

    view! {
        <AppShell title="Pod Tracker Status">
            <main class="shell">
                <section class="panel">
                    <h1>"Status"</h1>
                    <dl class="status-list">
                        <div>
                            <dt>"Database"</dt>
                            <dd>{database}</dd>
                        </div>
                        <div>
                            <dt>"Email"</dt>
                            <dd>{email}</dd>
                        </div>
                    </dl>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_signup(
    csrf_token: &str,
    error: Option<&str>,
    email: &str,
    display_name: &str,
) -> String {
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let email = email.to_owned();
    let display_name = display_name.to_owned();

    view! {
        <AppShell title="Sign up">
            <main class="shell">
                <section class="panel auth-panel">
                    <h1>"Sign up"</h1>
                    {error.map(|message| view! { <p class="form-error">{message}</p> })}
                    <form method="post" action="/signup" class="stack">
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>
                            "Email"
                            <input type="email" name="email" autocomplete="email" required value=email/>
                        </label>
                        <label>
                            "Display name"
                            <input type="text" name="display_name" autocomplete="name" required value=display_name/>
                        </label>
                        <label>
                            "Password"
                            <input type="password" name="password" autocomplete="new-password" required minlength="12"/>
                        </label>
                        <button type="submit">"Create account"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_login(csrf_token: &str, error: Option<&str>, email: &str) -> String {
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let email = email.to_owned();

    view! {
        <AppShell title="Log in">
            <main class="shell">
                <section class="panel auth-panel">
                    <h1>"Log in"</h1>
                    {error.map(|message| view! { <p class="form-error">{message}</p> })}
                    <form method="post" action="/login" class="stack">
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>
                            "Email"
                            <input type="email" name="email" autocomplete="email" required value=email/>
                        </label>
                        <label>
                            "Password"
                            <input type="password" name="password" autocomplete="current-password" required/>
                        </label>
                        <button type="submit">"Log in"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_dashboard(display_name: &str, csrf_token: &str) -> String {
    let display_name = display_name.to_owned();
    let csrf_token = csrf_token.to_owned();

    view! {
        <AppShell title="Dashboard">
            <main class="shell">
                <section class="panel">
                    <p class="eyebrow">"Dashboard"</p>
                    <h1>{display_name}</h1>
                    <nav class="actions" aria-label="Dashboard">
                        <a href="/events">"Events"</a>
                        <a href="/settings">"Settings"</a>
                    </nav>
                    <form method="post" action="/logout" class="inline-form">
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <button type="submit">"Log out"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_settings(email: &str, display_name: &str, csrf_token: &str) -> String {
    let email = email.to_owned();
    let display_name = display_name.to_owned();
    let csrf_token = csrf_token.to_owned();

    view! {
        <AppShell title="Settings">
            <main class="shell">
                <section class="panel">
                    <p class="eyebrow">"Settings"</p>
                    <h1>{display_name}</h1>
                    <dl class="status-list">
                        <div>
                            <dt>"Email"</dt>
                            <dd>{email}</dd>
                        </div>
                    </dl>
                    <form method="post" action="/logout" class="inline-form">
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <button type="submit">"Log out"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_placeholder(title: &'static str) -> String {
    view! {
        <AppShell title=title>
            <main class="shell">
                <section class="panel">
                    <h1>{title}</h1>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

#[component]
fn AppShell(title: &'static str, children: Children) -> impl IntoView {
    view! {
        <!DOCTYPE html>
        <html lang="en">
            <head>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1"/>
                <title>{title}</title>
                <link rel="stylesheet" href="/static/app.css"/>
            </head>
            <body>
                <header class="topbar">
                    <a class="brand" href="/">"Pod Tracker"</a>
                    <nav aria-label="Main">
                        <a href="/home">"Home"</a>
                        <a href="/events">"Events"</a>
                        <a href="/login">"Login"</a>
                        <a href="/observatory">"Observatory"</a>
                    </nav>
                </header>
                {children()}
            </body>
        </html>
    }
}
