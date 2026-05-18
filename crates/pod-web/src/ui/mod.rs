use leptos::prelude::*;
use pod_db::{
    EventRecord, EventRsvpRecord, EventWithRole, HouseRuleRecord, PlaygroupSettingsRecord,
    PlaygroupWithRole,
};
use time::{OffsetDateTime, UtcOffset};

use crate::server::{EventEditForm, EventForm, EventPageContext, RsvpForm};

pub fn render_home() -> String {
    view! {
        <AppShell title="Pod Tracker">
            <main class="shell home-shell">
                <section class="hero" aria-labelledby="home-title">
                    <div class="hero-copy">
                        <p class="eyebrow">"Commander night operations"</p>
                        <h1 id="home-title">"Pod Tracker"</h1>
                        <p class="lede">
                            "Run game night from invite to pod assignment to the meta snapshot afterward."
                        </p>
                        <nav class="actions" aria-label="Primary">
                            <a class="button primary" href="/home">"Open dashboard"</a>
                            <a class="button secondary" href="/signup">"Create account"</a>
                            <a class="button ghost" href="/status">"System status"</a>
                        </nav>
                    </div>
                    <div class="command-board" aria-label="Game night workflow preview">
                        <div class="board-header">
                            <span>"Tonight"</span>
                            <strong>"14 confirmed"</strong>
                        </div>
                        <div class="board-row">
                            <span>"RSVPs"</span>
                            <strong>"9 yes · 3 maybe · 2 waitlist"</strong>
                        </div>
                        <div class="board-row">
                            <span>"Decks"</span>
                            <strong>"11 declared"</strong>
                        </div>
                        <div class="board-row">
                            <span>"Pods"</span>
                            <strong>"3 proposed · 1 open seat"</strong>
                        </div>
                        <div class="board-footer">
                            <span>"SQL Observatory"</span>
                            <strong>"Pairing history ready"</strong>
                        </div>
                    </div>
                </section>
                <section class="ops-strip" aria-label="Product focus">
                    <div>
                        <span>"Plan"</span>
                        <strong>"Events, hosts, and privacy scopes"</strong>
                    </div>
                    <div>
                        <span>"Seat"</span>
                        <strong>"Fair pods with fewer repeat pairings"</strong>
                    </div>
                    <div>
                        <span>"Learn"</span>
                        <strong>"Meta health powered by PostgreSQL"</strong>
                    </div>
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
                <section class="page-header compact">
                    <p class="eyebrow">"Operations"</p>
                    <h1>"Status"</h1>
                    <dl class="status-list health-list">
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
            <main class="shell auth-shell">
                <section class="auth-panel">
                    <p class="eyebrow">"Account"</p>
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
            <main class="shell auth-shell">
                <section class="auth-panel">
                    <p class="eyebrow">"Account"</p>
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

pub fn render_dashboard(
    display_name: &str,
    csrf_token: &str,
    playgroups: &[PlaygroupWithRole],
) -> String {
    let display_name = display_name.to_owned();
    let csrf_token = csrf_token.to_owned();
    let playgroups = playgroups.to_vec();

    view! {
        <AppShell title="Dashboard">
            <main class="shell">
                <section class="page-header dashboard-header">
                    <p class="eyebrow">"Dashboard"</p>
                    <h1>{display_name}</h1>
                    <nav class="actions" aria-label="Dashboard actions">
                        <a class="button primary" href="/playgroups">"Playgroups"</a>
                        <a class="button secondary" href="/events">"Events"</a>
                        <a class="button ghost" href="/settings">"Settings"</a>
                    </nav>
                </section>
                <section class="workspace-panel">
                    <div class="section-heading">
                        <h2>"Playgroups"</h2>
                        <span>{playgroups.len()} " active"</span>
                    </div>
                    <PlaygroupList playgroups=playgroups/>
                    <form method="post" action="/logout" class="inline-form">
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <button class="button secondary" type="submit">"Log out"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_playgroups(
    csrf_token: &str,
    playgroups: &[PlaygroupWithRole],
    error: Option<&str>,
    name: &str,
    description: &str,
) -> String {
    let csrf_token = csrf_token.to_owned();
    let playgroups = playgroups.to_vec();
    let error = error.map(str::to_owned);
    let name = name.to_owned();
    let description = description.to_owned();

    view! {
        <AppShell title="Playgroups">
            <main class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Commander groups"</p>
                    <h1>"Playgroups"</h1>
                </section>
                <section class="split-layout">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Your playgroups"</h2>
                            <span>{playgroups.len()} " total"</span>
                        </div>
                        <PlaygroupList playgroups=playgroups/>
                    </div>
                    <form method="post" action="/playgroups" class="form-panel">
                        <h2>"New playgroup"</h2>
                        {error.map(|message| view! { <p class="form-error">{message}</p> })}
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>
                            "Name"
                            <input name="name" required value=name/>
                        </label>
                        <label>
                            "Description"
                            <textarea name="description" rows="4">{description}</textarea>
                        </label>
                        <button type="submit">"Create playgroup"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_playgroup_detail(
    playgroup: &PlaygroupWithRole,
    settings: Option<&PlaygroupSettingsRecord>,
    house_rules: &[HouseRuleRecord],
) -> String {
    let playgroup = playgroup.clone();
    let settings = settings.cloned();
    let house_rules = house_rules.to_vec();
    let has_house_rules = !house_rules.is_empty();

    view! {
        <AppShell title="Playgroup">
            <main class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Playgroup"</p>
                    <h1>{playgroup.name.clone()}</h1>
                    <p class="lede">{playgroup.description.clone()}</p>
                    <nav class="actions" aria-label="Playgroup actions">
                        <a class="button primary" href=format!("/playgroups/{}/events/new", playgroup.slug)>"New event"</a>
                        <a class="button secondary" href="/events">"All events"</a>
                    </nav>
                    <dl class="status-list">
                        <div>
                            <dt>"Role"</dt>
                            <dd>{playgroup.role.clone()}</dd>
                        </div>
                        {settings.map(|settings| view! {
                            <div>
                                <dt>"Event visibility"</dt>
                                <dd>{settings.default_event_visibility}</dd>
                            </div>
                        })}
                    </dl>
                </section>
                <section class="workspace-panel section-gap">
                    <div class="section-heading">
                        <h2>"House rules"</h2>
                        <span>{house_rules.len()} " visible"</span>
                    </div>
                    {if has_house_rules {
                        view! {
                            <div class="list">
                                {house_rules
                                    .into_iter()
                                    .map(|rule| view! {
                                        <article class="list-item">
                                            <div>
                                                <h3>{rule.title}</h3>
                                                <p>{rule.body}</p>
                                            </div>
                                            <span class="badge">
                                                {if rule.visible_to_guests { "guest visible" } else { "members" }}
                                            </span>
                                        </article>
                                    })
                                    .collect_view()}
                            </div>
                        }
                            .into_any()
                    } else {
                        view! { <p class="empty-state">"No house rules yet."</p> }.into_any()
                    }}
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_events(events: &[EventWithRole]) -> String {
    let events = events.to_vec();
    let has_events = !events.is_empty();

    view! {
        <AppShell title="Events">
            <main class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Schedule"</p>
                    <h1>"Events"</h1>
                    <nav class="actions" aria-label="Calendar">
                        <a class="button secondary" href="/calendar.ics">"Calendar feed"</a>
                    </nav>
                </section>
                {if has_events {
                    view! {
                        <section class="list">
                            {events.into_iter().map(|event| view! {
                                <article class="list-item">
                                    <div>
                                        <h2><a href=format!("/events/{}", event.id)>{event.title}</a></h2>
                                        <p>{event.playgroup_name} " · " {display_datetime(event.start_time)}</p>
                                    </div>
                                    <span class="badge">{event.visibility}</span>
                                </article>
                            }).collect_view()}
                        </section>
                    }.into_any()
                } else {
                    view! { <p class="empty-state">"No events yet."</p> }.into_any()
                }}
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_event_form(
    playgroup: &PlaygroupWithRole,
    csrf_token: &str,
    error: Option<&str>,
    form: Option<&EventForm>,
) -> String {
    let playgroup = playgroup.clone();
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let title = form
        .map(|form| form.title.as_str())
        .unwrap_or("")
        .to_owned();
    let description = form
        .map(|form| form.description.as_str())
        .unwrap_or("")
        .to_owned();
    let start_time = form
        .map(|form| form.start_time.as_str())
        .unwrap_or("")
        .to_owned();
    let end_time = form
        .map(|form| form.end_time.as_str())
        .unwrap_or("")
        .to_owned();
    let visibility = form
        .map(|form| form.visibility.as_str())
        .unwrap_or("members")
        .to_owned();
    let address_visibility = form
        .map(|form| form.address_visibility.as_str())
        .unwrap_or("rsvps")
        .to_owned();
    let location_name = form
        .map(|form| form.location_name.as_str())
        .unwrap_or("")
        .to_owned();
    let address_line1 = form
        .map(|form| form.address_line1.as_str())
        .unwrap_or("")
        .to_owned();
    let address_line2 = form
        .map(|form| form.address_line2.as_str())
        .unwrap_or("")
        .to_owned();
    let city = form.map(|form| form.city.as_str()).unwrap_or("").to_owned();
    let state_province = form
        .map(|form| form.state_province.as_str())
        .unwrap_or("")
        .to_owned();
    let postal_code = form
        .map(|form| form.postal_code.as_str())
        .unwrap_or("")
        .to_owned();
    let country = form
        .map(|form| form.country.as_str())
        .unwrap_or("")
        .to_owned();
    let location_notes = form
        .map(|form| form.location_notes.as_str())
        .unwrap_or("")
        .to_owned();

    view! {
        <AppShell title="New Event">
            <main class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">{playgroup.name.clone()}</p>
                    <h1>"New event"</h1>
                </section>
                <form method="post" action=format!("/playgroups/{}/events", playgroup.slug) class="form-panel wide-form">
                    {error.map(|message| view! { <p class="form-error">{message}</p> })}
                    <input type="hidden" name="csrf_token" value=csrf_token/>
                    <EventFields title=title description=description start_time=start_time end_time=end_time visibility=visibility/>
                    <fieldset>
                        <legend>"Location"</legend>
                        <label>"Name"<input name="location_name" value=location_name/></label>
                        <label>"Address line 1"<input name="address_line1" autocomplete="address-line1" value=address_line1/></label>
                        <label>"Address line 2"<input name="address_line2" autocomplete="address-line2" value=address_line2/></label>
                        <div class="field-grid">
                            <label>"City"<input name="city" autocomplete="address-level2" value=city/></label>
                            <label>"State"<input name="state_province" autocomplete="address-level1" value=state_province/></label>
                            <label>"Postal code"<input name="postal_code" autocomplete="postal-code" value=postal_code/></label>
                        </div>
                        <label>"Country"<input name="country" autocomplete="country-name" value=country/></label>
                        <label>"Notes"<textarea name="location_notes" rows="2">{location_notes}</textarea></label>
                        <label>
                            "Address visibility"
                            <select name="address_visibility">
                                <option value="rsvps" selected=address_visibility == "rsvps">"Confirmed RSVPs"</option>
                                <option value="members" selected=address_visibility == "members">"Members"</option>
                                <option value="hidden" selected=address_visibility == "hidden">"Hosts and admins"</option>
                                <option value="public" selected=address_visibility == "public">"Public"</option>
                            </select>
                        </label>
                    </fieldset>
                    <button class="button primary" type="submit">"Save event"</button>
                </form>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_event_edit(
    event: &EventWithRole,
    csrf_token: &str,
    error: Option<&str>,
    form: Option<&EventEditForm>,
) -> String {
    let event = event.clone();
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let title = form
        .map(|form| form.title.as_str())
        .unwrap_or(&event.title)
        .to_owned();
    let description = form
        .map(|form| form.description.as_str())
        .unwrap_or(&event.description)
        .to_owned();
    let start_time = form
        .map(|form| form.start_time.clone())
        .unwrap_or_else(|| datetime_local_value(event.start_time));
    let end_time = form
        .map(|form| form.end_time.clone())
        .unwrap_or_else(|| event.end_time.map(datetime_local_value).unwrap_or_default());
    let visibility = form
        .map(|form| form.visibility.as_str())
        .unwrap_or(&event.visibility)
        .to_owned();

    view! {
        <AppShell title="Edit Event">
            <main class="shell">
                <form method="post" action=format!("/events/{}/edit", event.id) class="form-panel wide-form">
                    <p class="eyebrow">"Event"</p>
                    <h1>"Edit event"</h1>
                    {error.map(|message| view! { <p class="form-error">{message}</p> })}
                    <input type="hidden" name="csrf_token" value=csrf_token/>
                    <EventFields title=title description=description start_time=start_time end_time=end_time visibility=visibility/>
                    <button class="button primary" type="submit">"Save changes"</button>
                </form>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_event_detail(
    event: &EventWithRole,
    context: &EventPageContext,
    csrf_token: &str,
) -> String {
    let event = event.clone();
    let context = context.clone();
    let csrf_token = csrf_token.to_owned();
    let public_url = (event.visibility == "public_safe")
        .then(|| {
            event
                .invite_token
                .as_ref()
                .map(|token| format!("/e/{token}"))
        })
        .flatten();
    let invite_url = event
        .invite_token
        .as_ref()
        .map(|token| format!("/rsvp/{token}"));

    view! {
        <AppShell title="Event">
            <main class="shell">
                <section class="page-header">
                    <p class="eyebrow">{event.playgroup_name.clone()}</p>
                    <h1>{event.title.clone()}</h1>
                    <p class="lede">{display_datetime(event.start_time)}</p>
                    <nav class="actions" aria-label="Event actions">
                        {context.can_edit.then(|| view! { <a class="button primary" href=format!("/events/{}/edit", event.id)>"Edit"</a> })}
                        {public_url.map(|url| view! { <a class="button secondary" href=url>"Public page"</a> })}
                        {invite_url.map(|url| view! { <a class="button ghost" href=url>"Invite RSVP"</a> })}
                    </nav>
                    <p class="body-copy">{event.description.clone()}</p>
                    <LocationBlock location=context.location.clone() show_address=context.show_address/>
                </section>
                <section class="split-layout">
                    <RsvpPanel event_id=event.id csrf_token=csrf_token user_rsvp=context.user_rsvp.clone()/>
                    <AttendeeList rsvps=context.rsvps/>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_public_event(event: &EventRecord, context: &EventPageContext) -> String {
    let event = event.clone();
    let context = context.clone();
    let invite_url = event
        .invite_token
        .as_ref()
        .map(|token| format!("/rsvp/{token}"));

    view! {
        <AppShell title="Event">
            <main class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Event"</p>
                    <h1>{event.title.clone()}</h1>
                    <p class="lede">{display_datetime(event.start_time)}</p>
                    <p class="body-copy">{event.description.clone()}</p>
                    <LocationBlock location=context.location show_address=context.show_address/>
                    <nav class="actions" aria-label="Public event">
                        {invite_url.map(|url| view! { <a class="button primary" href=url>"RSVP"</a> })}
                    </nav>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_guest_rsvp(
    event: &EventRecord,
    context: &EventPageContext,
    csrf_token: &str,
    error: Option<&str>,
    form: Option<&RsvpForm>,
) -> String {
    let event = event.clone();
    let context = context.clone();
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let guest_name = form
        .map(|form| form.guest_name.as_str())
        .unwrap_or("")
        .to_owned();
    let status = form
        .map(|form| form.status.as_str())
        .unwrap_or("yes")
        .to_owned();
    let notes = form
        .map(|form| form.notes.as_str())
        .unwrap_or("")
        .to_owned();

    view! {
        <AppShell title="RSVP">
            <main class="shell auth-shell">
                <form method="post" action=format!("/rsvp/{}", event.invite_token.clone().unwrap_or_default()) class="form-panel">
                    <p class="eyebrow">"Guest RSVP"</p>
                    <h1>{event.title.clone()}</h1>
                    <p class="lede">{display_datetime(event.start_time)}</p>
                    <LocationBlock location=context.location show_address=context.show_address/>
                    {error.map(|message| view! { <p class="form-error">{message}</p> })}
                    <input type="hidden" name="csrf_token" value=csrf_token/>
                    <label>"Name"<input name="guest_name" required value=guest_name/></label>
                    <RsvpFields status=status arrival_time="".to_owned() leaving_time="".to_owned() guest_count="0".to_owned() travel_buffer_minutes="".to_owned() notes=notes/>
                    <button class="button primary" type="submit">"Save RSVP"</button>
                </form>
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
                <section class="page-header compact">
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
                        <button class="button secondary" type="submit">"Log out"</button>
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
                <section class="page-header compact">
                    <h1>{title}</h1>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

#[component]
fn PlaygroupList(playgroups: Vec<PlaygroupWithRole>) -> impl IntoView {
    let has_playgroups = !playgroups.is_empty();

    view! {
        {if has_playgroups {
            view! {
                <div class="list">
                    {playgroups
                        .into_iter()
                        .map(|playgroup| view! {
                            <article class="list-item">
                                <div>
                                    <h3>
                                        <a href=format!("/playgroups/{}", playgroup.slug)>{playgroup.name}</a>
                                    </h3>
                                    <p>{playgroup.description}</p>
                                </div>
                                <span class="badge">{playgroup.role}</span>
                            </article>
                        })
                        .collect_view()}
                </div>
            }
                .into_any()
        } else {
            view! { <p class="empty-state">"No playgroups yet."</p> }.into_any()
        }}
    }
}

#[component]
fn EventFields(
    title: String,
    description: String,
    start_time: String,
    end_time: String,
    visibility: String,
) -> impl IntoView {
    view! {
        <label>"Title"<input name="title" required value=title/></label>
        <label>"Description"<textarea name="description" rows="3">{description}</textarea></label>
        <div class="field-grid">
            <label>"Start"<input type="datetime-local" name="start_time" required value=start_time/></label>
            <label>"End"<input type="datetime-local" name="end_time" value=end_time/></label>
        </div>
        <label>
            "Visibility"
            <select name="visibility">
                <option value="members" selected=visibility == "members">"Members"</option>
                <option value="invite_only" selected=visibility == "invite_only">"Invite only"</option>
                <option value="public_safe" selected=visibility == "public_safe">"Public safe"</option>
            </select>
        </label>
    }
}

#[component]
fn RsvpPanel(
    event_id: uuid::Uuid,
    csrf_token: String,
    user_rsvp: Option<EventRsvpRecord>,
) -> impl IntoView {
    let status = user_rsvp
        .as_ref()
        .map(|rsvp| rsvp.status.as_str())
        .unwrap_or("yes")
        .to_owned();
    let arrival_time = user_rsvp
        .as_ref()
        .and_then(|rsvp| rsvp.arrival_time)
        .map(datetime_local_value)
        .unwrap_or_default();
    let leaving_time = user_rsvp
        .as_ref()
        .and_then(|rsvp| rsvp.leaving_time)
        .map(datetime_local_value)
        .unwrap_or_default();
    let guest_count = user_rsvp
        .as_ref()
        .map(|rsvp| rsvp.guest_count.to_string())
        .unwrap_or_else(|| "0".to_owned());
    let travel_buffer_minutes = user_rsvp
        .as_ref()
        .and_then(|rsvp| rsvp.travel_buffer_minutes)
        .map(|minutes| minutes.to_string())
        .unwrap_or_default();
    let notes = user_rsvp
        .as_ref()
        .map(|rsvp| rsvp.notes.clone())
        .unwrap_or_default();

    view! {
        <form method="post" action=format!("/events/{event_id}/rsvp") class="form-panel">
            <h2>"Your RSVP"</h2>
            <input type="hidden" name="csrf_token" value=csrf_token/>
            <RsvpFields
                status=status
                arrival_time=arrival_time
                leaving_time=leaving_time
                guest_count=guest_count
                travel_buffer_minutes=travel_buffer_minutes
                notes=notes
            />
            <button class="button primary" type="submit">"Save RSVP"</button>
        </form>
    }
}

#[component]
fn RsvpFields(
    status: String,
    arrival_time: String,
    leaving_time: String,
    guest_count: String,
    travel_buffer_minutes: String,
    notes: String,
) -> impl IntoView {
    view! {
        <label>
            "Status"
            <select name="status">
                <option value="yes" selected=status == "yes">"Yes"</option>
                <option value="maybe" selected=status == "maybe">"Maybe"</option>
                <option value="no" selected=status == "no">"No"</option>
                <option value="waitlist" selected=status == "waitlist">"Waitlist"</option>
            </select>
        </label>
        <div class="field-grid">
            <label>"Arrival"<input type="datetime-local" name="arrival_time" value=arrival_time/></label>
            <label>"Leaving"<input type="datetime-local" name="leaving_time" value=leaving_time/></label>
        </div>
        <div class="field-grid">
            <label>"Guests"<input type="number" min="0" name="guest_count" value=guest_count/></label>
            <label>"Travel buffer"<input type="number" min="0" name="travel_buffer_minutes" value=travel_buffer_minutes/></label>
        </div>
        <label>"Notes"<textarea name="notes" rows="3">{notes}</textarea></label>
    }
}

#[component]
fn AttendeeList(rsvps: Vec<EventRsvpRecord>) -> impl IntoView {
    let has_rsvps = !rsvps.is_empty();

    view! {
        <section class="panel">
            <h2>"Attendees"</h2>
            {if has_rsvps {
                view! {
                    <div class="list">
                        {rsvps.into_iter().map(|rsvp| {
                            let name = rsvp.guest_name.unwrap_or_else(|| "Member".to_owned());
                            view! {
                                <article class="list-item">
                                    <div>
                                        <h3>{name}</h3>
                                        <p>{rsvp.notes}</p>
                                    </div>
                                    <span class="badge">{rsvp.status}</span>
                                </article>
                            }
                        }).collect_view()}
                    </div>
                }.into_any()
            } else {
                view! { <p class="empty-state">"No RSVPs yet."</p> }.into_any()
            }}
        </section>
    }
}

#[component]
fn LocationBlock(
    location: Option<pod_db::EventLocationRecord>,
    show_address: bool,
) -> impl IntoView {
    view! {
        {location.map(|location| view! {
            <div class="location-block">
                <h2>{location.name}</h2>
                {if show_address {
                    view! {
                        <address>
                            {location.address_line1.map(|line| view! { <span>{line}</span> })}
                            {location.address_line2.map(|line| view! { <span>{line}</span> })}
                            <span>{city_line(&location.city, &location.state_province, &location.postal_code)}</span>
                            {location.country.map(|country| view! { <span>{country}</span> })}
                        </address>
                    }.into_any()
                } else {
                    view! { <p class="empty-state">"Address hidden"</p> }.into_any()
                }}
                {(!location.notes.is_empty()).then(|| view! { <p>{location.notes}</p> })}
            </div>
        })}
    }
}

fn datetime_local_value(value: OffsetDateTime) -> String {
    let value = value.to_offset(UtcOffset::UTC);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}",
        value.year(),
        u8::from(value.month()),
        value.day(),
        value.hour(),
        value.minute()
    )
}

fn display_datetime(value: OffsetDateTime) -> String {
    let value = value.to_offset(UtcOffset::UTC);
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02} UTC",
        value.year(),
        u8::from(value.month()),
        value.day(),
        value.hour(),
        value.minute()
    )
}

fn city_line(
    city: &Option<String>,
    state: &Option<String>,
    postal_code: &Option<String>,
) -> String {
    let mut line = String::new();
    if let Some(city) = city {
        line.push_str(city);
    }
    if let Some(state) = state {
        if !line.is_empty() {
            line.push_str(", ");
        }
        line.push_str(state);
    }
    if let Some(postal_code) = postal_code {
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(postal_code);
    }
    line
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
                    <a class="brand" href="/">
                        <span class="brand-mark" aria-hidden="true">"PT"</span>
                        <span>"Pod Tracker"</span>
                    </a>
                    <nav class="main-nav" aria-label="Main">
                        <a href="/home">"Home"</a>
                        <a href="/playgroups">"Playgroups"</a>
                        <a href="/events">"Events"</a>
                        <a href="/observatory">"Observatory"</a>
                        <a class="nav-login" href="/login">"Login"</a>
                    </nav>
                </header>
                {children()}
            </body>
        </html>
    }
}
