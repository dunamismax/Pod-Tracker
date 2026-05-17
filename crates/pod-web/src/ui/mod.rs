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
                        <a href="/observatory">"Observatory"</a>
                    </nav>
                </header>
                {children()}
            </body>
        </html>
    }
}
