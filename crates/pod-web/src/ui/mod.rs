use leptos::prelude::*;
use pod_db::{
    CardSearchResult, CollectionCardRecord, CollectionRecord, DeckBracketSnapshotRecord,
    DeckMissingCardRecord, DeckRecord, EventDeckDeclarationWithDeck, EventRecord, EventRsvpRecord,
    EventWithRole, GameWithPlayers, HouseRuleRecord, MetaDashboard, MetaDistributionMetric,
    PlaygroupSettingsRecord, PlaygroupWithRole, PodWithSeats, WishlistCardRecord,
    WishlistMissingCardRecord, WishlistRecord,
};
use time::{OffsetDateTime, UtcOffset};

use crate::server::{
    CollectionForm, DeckForm, EventEditForm, EventForm, EventPageContext, RsvpForm, WishlistForm,
};

pub fn render_home() -> String {
    view! {
        <AppShell title="Pod Tracker">
            <main id="main" class="shell home-shell">
                <section class="hero" aria-labelledby="home-title">
                    <div class="hero-copy">
                        <p class="eyebrow">"Commander night operations"</p>
                        <h1 id="home-title">"Pod Tracker"</h1>
                        <p class="lede">
                            "Run game night from invite to pod assignment to the meta snapshot afterward."
                        </p>
                        <dl class="hero-metrics" aria-label="Game night priorities">
                            <div>
                                <dt>"Fast loop"</dt>
                                <dd>"RSVPs, decks, pods, results"</dd>
                            </div>
                            <div>
                                <dt>"Private by scope"</dt>
                                <dd>"Host details only where permitted"</dd>
                            </div>
                        </dl>
                        <nav class="actions" aria-label="Primary">
                            <a class="button primary" href="/home">"Open dashboard"</a>
                            <a class="button secondary" href="/signup">"Create account"</a>
                            <a class="button ghost" href="/status">"System status"</a>
                        </nav>
                    </div>
                    <div class="event-console" aria-label="Game night workflow preview">
                        <div class="console-header">
                            <div>
                                <span>"Friday Commander"</span>
                                <strong>"Tonight at 6:30 PM"</strong>
                            </div>
                            <span class="status-pill">"Ready"</span>
                        </div>
                        <div class="console-matrix">
                            <div>
                                <span>"Confirmed"</span>
                                <strong>"14"</strong>
                            </div>
                            <div>
                                <span>"Decks"</span>
                                <strong>"11"</strong>
                            </div>
                            <div>
                                <span>"Pods"</span>
                                <strong>"3"</strong>
                            </div>
                        </div>
                        <div class="pod-stack">
                            <article>
                                <span>"Pod A"</span>
                                <strong>"Bracket 2-3 · no repeat pairs"</strong>
                            </article>
                            <article>
                                <span>"Pod B"</span>
                                <strong>"Guest seat locked · one open slot"</strong>
                            </article>
                            <article>
                                <span>"Pod C"</span>
                                <strong>"Late arrivals grouped"</strong>
                            </article>
                        </div>
                        <div class="sql-strip">
                            <span>"SQL Observatory"</span>
                            <code>"matchup_freshness_score(event_id)"</code>
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
            <main id="main" class="shell">
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

pub fn render_error_page(status_code: u16, title: &str, message: &str) -> String {
    let status_code = status_code.to_string();
    let title = title.to_owned();
    let message = message.to_owned();

    view! {
        <AppShell title="Pod Tracker Error">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">{status_code}</p>
                    <h1>{title}</h1>
                    <p class="body-copy">{message}</p>
                    <nav class="actions" aria-label="Error recovery">
                        <a class="button primary" href="/home">"Home"</a>
                        <a class="button ghost" href="/status">"Status"</a>
                    </nav>
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
            <main id="main" class="shell auth-shell">
                <section class="auth-panel">
                    <p class="eyebrow">"Account"</p>
                    <h1>"Sign up"</h1>
                    <p class="body-copy">"Create the host account that owns playgroups, event privacy, RSVPs, and calendar access."</p>
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
                        <button class="button primary" type="submit">"Create account"</button>
                    </form>
                    <p class="auth-note">
                        "Already have an account? "
                        <a href="/login">"Log in"</a>
                    </p>
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
            <main id="main" class="shell auth-shell">
                <section class="auth-panel">
                    <p class="eyebrow">"Account"</p>
                    <h1>"Log in"</h1>
                    <p class="body-copy">"Open the operating view for playgroups, events, RSVPs, and invite-scoped guest pages."</p>
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
                        <button class="button primary" type="submit">"Log in"</button>
                    </form>
                    <p class="auth-note">
                        "Need an account? "
                        <a href="/signup">"Create one"</a>
                    </p>
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
        <AppShell title="Dashboard" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header dashboard-header">
                    <div>
                        <p class="eyebrow">"Dashboard"</p>
                        <h1>{display_name}</h1>
                    </div>
                    <nav class="actions" aria-label="Dashboard actions">
                        <a class="button primary" href="/playgroups">"Playgroups"</a>
                        <a class="button secondary" href="/events">"Events"</a>
                        <a class="button secondary" href="/decks">"Decks"</a>
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
        <AppShell title="Playgroups" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Commander groups"</p>
                    <h1>"Playgroups"</h1>
                    <p class="body-copy">"Create and manage the playgroups that own event access, roles, house rules, and schedule defaults."</p>
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
        <AppShell title="Playgroup" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
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
        <AppShell title="Events" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
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
                    view! { <p class="empty-state">"No events yet. Create one from a playgroup page."</p> }.into_any()
                }}
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_decks(
    csrf_token: &str,
    decks: &[DeckRecord],
    playgroups: &[PlaygroupWithRole],
    search: &str,
    error: Option<&str>,
    form: Option<&DeckForm>,
) -> String {
    let csrf_token = csrf_token.to_owned();
    let decks = decks.to_vec();
    let playgroups = playgroups.to_vec();
    let search = search.to_owned();
    let error = error.map(str::to_owned);
    let name = form.map(|form| form.name.as_str()).unwrap_or("").to_owned();
    let commander = form
        .map(|form| form.commander.as_str())
        .unwrap_or("")
        .to_owned();
    let color_identity = form
        .map(|form| form.color_identity.as_str())
        .unwrap_or("")
        .to_owned();
    let claimed_bracket = form
        .map(|form| form.claimed_bracket.as_str())
        .unwrap_or("")
        .to_owned();
    let archetype = form
        .map(|form| form.archetype.as_str())
        .unwrap_or("")
        .to_owned();
    let tags = form.map(|form| form.tags.as_str()).unwrap_or("").to_owned();
    let visibility = form
        .map(|form| form.visibility.as_str())
        .unwrap_or("private")
        .to_owned();
    let playgroup_id = form
        .map(|form| form.playgroup_id.as_str())
        .unwrap_or("")
        .to_owned();
    let status = form
        .map(|form| form.status.as_str())
        .unwrap_or("active")
        .to_owned();
    let game_changers_count = form
        .map(|form| form.game_changers_count.as_str())
        .unwrap_or("0")
        .to_owned();
    let tutor_density = form
        .map(|form| form.tutor_density.as_str())
        .unwrap_or("none")
        .to_owned();
    let has_infinite_combo = form.is_some_and(|form| form.has_infinite_combo);
    let has_fast_mana = form.is_some_and(|form| form.has_fast_mana);
    let has_extra_turns = form.is_some_and(|form| form.has_extra_turns);
    let has_mass_land_denial = form.is_some_and(|form| form.has_mass_land_denial);
    let salt_notes = form
        .map(|form| form.salt_notes.as_str())
        .unwrap_or("")
        .to_owned();
    let notes = form
        .map(|form| form.notes.as_str())
        .unwrap_or("")
        .to_owned();
    let has_decks = !decks.is_empty();

    view! {
        <AppShell title="Decks" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Deck registry"</p>
                    <h1>"Decks"</h1>
                    <form method="get" action="/decks" class="search-form" role="search">
                        <label>
                            "Search"
                            <input name="q" value=search placeholder="Commander, archetype, tag"/>
                        </label>
                        <button class="button secondary" type="submit">"Search"</button>
                    </form>
                </section>
                <section class="split-layout wide-left">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Registry"</h2>
                            <span>{decks.len()} " visible"</span>
                        </div>
                        {if has_decks {
                            view! { <DeckList decks=decks/> }.into_any()
                        } else {
                            view! { <p class="empty-state">"No visible decks yet."</p> }.into_any()
                        }}
                    </div>
                    <form method="post" action="/decks" class="form-panel">
                        <h2>"New deck"</h2>
                        {error.map(|message| view! { <p class="form-error">{message}</p> })}
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>"Name"<input name="name" required value=name/></label>
                        <label>"Commander"<input name="commander" required value=commander/></label>
                        <div class="field-grid">
                            <label>"Color identity"<input name="color_identity" value=color_identity placeholder="WUBRG"/></label>
                            <label>"Claimed bracket"<input name="claimed_bracket" value=claimed_bracket/></label>
                        </div>
                        <label>"Archetype"<input name="archetype" value=archetype/></label>
                        <label>"Tags"<input name="tags" value=tags placeholder="tokens, midrange"/></label>
                        <div class="field-grid">
                            <label>
                                "Visibility"
                                <select name="visibility">
                                    <option value="private" selected=visibility == "private">"Private"</option>
                                    <option value="playgroup" selected=visibility == "playgroup">"Playgroup"</option>
                                    <option value="public" selected=visibility == "public">"Public"</option>
                                </select>
                            </label>
                            <label>
                                "Status"
                                <select name="status">
                                    <option value="active" selected=status == "active">"Active"</option>
                                    <option value="retired" selected=status == "retired">"Retired"</option>
                                </select>
                            </label>
                        </div>
                        <label>
                            "Playgroup"
                            <select name="playgroup_id">
                                <option value="" selected=playgroup_id.is_empty()>"None"</option>
                                {playgroups.into_iter().map(|playgroup| {
                                    let id = playgroup.id.to_string();
                                    view! {
                                        <option value=id.clone() selected=playgroup_id == id>
                                            {playgroup.name}
                                        </option>
                                    }
                                }).collect_view()}
                            </select>
                        </label>
                        <fieldset>
                            <legend>"Metadata"</legend>
                            <div class="field-grid">
                                <label>"Game Changers"<input type="number" min="0" name="game_changers_count" value=game_changers_count/></label>
                                <label>
                                    "Tutor density"
                                    <select name="tutor_density">
                                        <option value="none" selected=tutor_density == "none">"None"</option>
                                        <option value="low" selected=tutor_density == "low">"Low"</option>
                                        <option value="medium" selected=tutor_density == "medium">"Medium"</option>
                                        <option value="high" selected=tutor_density == "high">"High"</option>
                                    </select>
                                </label>
                            </div>
                            <div class="check-grid">
                                <label><input type="checkbox" name="has_infinite_combo" value="true" checked=has_infinite_combo/>"Infinite combo"</label>
                                <label><input type="checkbox" name="has_fast_mana" value="true" checked=has_fast_mana/>"Fast mana"</label>
                                <label><input type="checkbox" name="has_extra_turns" value="true" checked=has_extra_turns/>"Extra turns"</label>
                                <label><input type="checkbox" name="has_mass_land_denial" value="true" checked=has_mass_land_denial/>"Mass land denial"</label>
                            </div>
                            <label>"Salt notes"<textarea name="salt_notes" rows="2">{salt_notes}</textarea></label>
                        </fieldset>
                        <label>"Notes"<textarea name="notes" rows="3">{notes}</textarea></label>
                        <button class="button primary" type="submit">"Save deck"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_deck_detail(
    deck: &DeckRecord,
    csrf_token: &str,
    snapshot: Option<&DeckBracketSnapshotRecord>,
    import_error: Option<&str>,
    can_export: bool,
) -> String {
    let deck = deck.clone();
    let tags = deck.tags.join(", ");
    let csrf_token = csrf_token.to_owned();
    let snapshot = snapshot.cloned();
    let import_error = import_error.map(str::to_owned);

    view! {
        <AppShell title="Deck" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Deck"</p>
                    <h1>{deck.name.clone()}</h1>
                    <p class="lede">{deck.commander.clone()}</p>
                    <nav class="actions" aria-label="Deck actions">
                        <a class="button secondary" href="/decks">"All decks"</a>
                        {can_export.then(|| view! {
                            <a class="button secondary" href=format!("/decks/{}/export/plain-text", deck.id)>"Plain text"</a>
                        })}
                        {can_export.then(|| view! {
                            <a class="button secondary" href=format!("/decks/{}/export/moxfield", deck.id)>"Moxfield"</a>
                        })}
                        {can_export.then(|| view! {
                            <a class="button secondary" href=format!("/decks/{}/export/archidekt", deck.id)>"Archidekt"</a>
                        })}
                    </nav>
                    <dl class="status-list">
                        <div><dt>"Color identity"</dt><dd>{deck.color_identity.clone()}</dd></div>
                        <div><dt>"Claimed bracket"</dt><dd>{deck.claimed_bracket.clone()}</dd></div>
                        <div><dt>"Archetype"</dt><dd>{deck.archetype.clone()}</dd></div>
                        <div><dt>"Visibility"</dt><dd>{deck.visibility.clone()}</dd></div>
                        <div><dt>"Status"</dt><dd>{deck.status.clone()}</dd></div>
                        <div><dt>"Tags"</dt><dd>{tags}</dd></div>
                    </dl>
                </section>
                <section class="split-layout">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Deck notes"</h2>
                            <span>{deck.game_changers_count} " Game Changers"</span>
                        </div>
                        <p class="body-copy">{deck.notes.clone()}</p>
                    </div>
                    <div class="panel">
                        <h2>"Flags"</h2>
                        <dl class="compact-list">
                            <div><dt>"Infinite combo"</dt><dd>{yes_no(deck.has_infinite_combo)}</dd></div>
                            <div><dt>"Fast mana"</dt><dd>{yes_no(deck.has_fast_mana)}</dd></div>
                            <div><dt>"Tutor density"</dt><dd>{deck.tutor_density.clone()}</dd></div>
                            <div><dt>"Extra turns"</dt><dd>{yes_no(deck.has_extra_turns)}</dd></div>
                            <div><dt>"Mass land denial"</dt><dd>{yes_no(deck.has_mass_land_denial)}</dd></div>
                        </dl>
                        {(!deck.salt_notes.is_empty()).then(|| view! { <p class="body-copy">{deck.salt_notes}</p> })}
                    </div>
                </section>
                <section class="split-layout wide-left section-gap">
                    <form method="post" action=format!("/decks/{}/import", deck.id) class="form-panel">
                        <h2>"Decklist import"</h2>
                        {import_error.map(|message| view! { <p class="form-error">{message}</p> })}
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>
                            "Plain text"
                            <textarea name="decklist" rows="12" placeholder={"Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n1 Sol Ring"}></textarea>
                        </label>
                        <button class="button primary" type="submit">"Import list"</button>
                    </form>
                    <div class="panel">
                        <h2>"Bracket check"</h2>
                        {if let Some(snapshot) = snapshot {
                            view! {
                                <dl class="compact-list">
                                    <div><dt>"Color identity"</dt><dd>{snapshot.color_identity.clone()}</dd></div>
                                    <div><dt>"Commanders"</dt><dd>{snapshot.commander_names.join(" / ")}</dd></div>
                                    <div><dt>"Game Changers"</dt><dd>{snapshot.game_changers_count}</dd></div>
                                </dl>
                                {if snapshot.warnings.is_empty() {
                                    view! { <p class="empty-state">"No bracket warnings for the latest import."</p> }.into_any()
                                } else {
                                    view! {
                                        <ul class="plain-list">
                                            {snapshot.warnings.into_iter().map(|warning| view! {
                                                <li>{warning}</li>
                                            }).collect_view()}
                                        </ul>
                                    }.into_any()
                                }}
                            }.into_any()
                        } else {
                            view! { <p class="empty-state">"No imported decklist snapshot yet."</p> }.into_any()
                        }}
                    </div>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub struct CardSearchView<'a> {
    pub query: &'a str,
    pub color_identity: &'a str,
    pub commander_legal: bool,
    pub max_mana_value: &'a str,
    pub type_line: &'a str,
    pub max_usd: &'a str,
    pub game_changer: bool,
}

pub fn render_cards(cards: &[CardSearchResult], search: CardSearchView<'_>) -> String {
    let cards = cards.to_vec();
    let query = search.query.to_owned();
    let color_identity = search.color_identity.to_owned();
    let max_mana_value = search.max_mana_value.to_owned();
    let type_line = search.type_line.to_owned();
    let max_usd = search.max_usd.to_owned();
    let commander_legal = search.commander_legal;
    let game_changer = search.game_changer;
    let has_cards = !cards.is_empty();

    view! {
        <AppShell title="Cards" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"Scryfall local index"</p>
                    <h1>"Cards"</h1>
                    <form method="get" action="/cards" class="search-form" role="search">
                        <label>
                            "Search"
                            <input name="q" value=query.clone() placeholder="Name, type, oracle text"/>
                        </label>
                        <button class="button secondary" type="submit">"Search"</button>
                    </form>
                </section>
                <section class="split-layout wide-left">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Results"</h2>
                            <span>{cards.len()} " cards"</span>
                        </div>
                        {if has_cards {
                            view! {
                                <div class="list">
                                    {cards.into_iter().map(|card| {
                                        let colors = display_color_identity(&card.color_identity);
                                        let price = card.usd
                                            .map(|usd| format!("${usd:.2}"))
                                            .unwrap_or_else(|| "No price".to_owned());
                                        view! {
                                            <article class="list-item">
                                                <div>
                                                    <h2>{card.name}</h2>
                                                    <p>{card.type_line}</p>
                                                    <p>{truncate_text(&card.oracle_text, 180)}</p>
                                                </div>
                                                <dl class="compact-list inline">
                                                    <div><dt>"CI"</dt><dd>{colors}</dd></div>
                                                    <div><dt>"MV"</dt><dd>{card.mana_value.map(display_number).unwrap_or_else(|| "-".to_owned())}</dd></div>
                                                    <div><dt>"USD"</dt><dd>{price}</dd></div>
                                                    <div><dt>"Commander"</dt><dd>{yes_no(card.commander_legal)}</dd></div>
                                                </dl>
                                            </article>
                                        }
                                    }).collect_view()}
                                </div>
                            }.into_any()
                        } else {
                            view! { <p class="empty-state">"No local cards match those filters."</p> }.into_any()
                        }}
                    </div>
                    <form method="get" action="/cards" class="form-panel">
                        <h2>"Filters"</h2>
                        <label>"Query"<input name="q" value=query/></label>
                        <label>"Color identity"<input name="color_identity" value=color_identity placeholder="WUBRG"/></label>
                        <label>"Type"<input name="type_line" value=type_line placeholder="Creature, instant"/></label>
                        <div class="field-grid">
                            <label>"Max mana value"<input name="max_mana_value" inputmode="decimal" value=max_mana_value/></label>
                            <label>"Max USD"<input name="max_usd" inputmode="decimal" value=max_usd/></label>
                        </div>
                        <label class="checkbox-row">
                            <input type="checkbox" name="commander_legal" value="true" checked=commander_legal/>
                            "Commander legal"
                        </label>
                        <label class="checkbox-row">
                            <input type="checkbox" name="game_changer" value="true" checked=game_changer/>
                            "Game Changer"
                        </label>
                        <button class="button primary" type="submit">"Apply filters"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_collections(
    csrf_token: &str,
    collections: &[CollectionRecord],
    playgroups: &[PlaygroupWithRole],
    error: Option<&str>,
    form: Option<&CollectionForm>,
) -> String {
    let csrf_token = csrf_token.to_owned();
    let collections = collections.to_vec();
    let playgroups = playgroups.to_vec();
    let error = error.map(str::to_owned);
    let name = form.map(|form| form.name.as_str()).unwrap_or("").to_owned();
    let visibility = form
        .map(|form| form.visibility.as_str())
        .unwrap_or("private")
        .to_owned();
    let playgroup_id = form
        .map(|form| form.playgroup_id.as_str())
        .unwrap_or("")
        .to_owned();
    let notes = form
        .map(|form| form.notes.as_str())
        .unwrap_or("")
        .to_owned();
    let has_collections = !collections.is_empty();

    view! {
        <AppShell title="Collections" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"Collection tracking"</p>
                    <h1>"Collections"</h1>
                </section>
                <section class="split-layout wide-left">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Visible collections"</h2>
                            <span>{collections.len()} " collections"</span>
                        </div>
                        {if has_collections {
                            view! {
                                <div class="list">
                                    {collections.into_iter().map(|collection| view! {
                                        <article class="list-item">
                                            <div>
                                                <h2><a href=format!("/collections/{}", collection.id)>{collection.name}</a></h2>
                                                <p>{collection.notes}</p>
                                            </div>
                                            <dl class="compact-list inline">
                                                <div><dt>"Visibility"</dt><dd>{collection.visibility}</dd></div>
                                            </dl>
                                        </article>
                                    }).collect_view()}
                                </div>
                            }.into_any()
                        } else {
                            view! { <p class="empty-state">"No visible collections yet."</p> }.into_any()
                        }}
                    </div>
                    <form method="post" action="/collections" class="form-panel">
                        <h2>"New collection"</h2>
                        {error.map(|message| view! { <p class="form-error">{message}</p> })}
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>"Name"<input name="name" required value=name/></label>
                        <div class="field-grid">
                            <label>
                                "Visibility"
                                <select name="visibility">
                                    <option value="private" selected=visibility == "private">"Private"</option>
                                    <option value="playgroup" selected=visibility == "playgroup">"Playgroup"</option>
                                    <option value="public" selected=visibility == "public">"Public"</option>
                                </select>
                            </label>
                            <label>
                                "Playgroup"
                                <select name="playgroup_id">
                                    <option value="" selected=playgroup_id.is_empty()>"None"</option>
                                    {playgroups.into_iter().map(|playgroup| {
                                        let id = playgroup.id.to_string();
                                        view! {
                                            <option value=id.clone() selected=playgroup_id == id>
                                                {playgroup.name}
                                            </option>
                                        }
                                    }).collect_view()}
                                </select>
                            </label>
                        </div>
                        <label>"Notes"<textarea name="notes" rows="3">{notes}</textarea></label>
                        <button class="button primary" type="submit">"Save collection"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_collection_detail(
    collection: &CollectionRecord,
    cards: &[CollectionCardRecord],
    decks: &[DeckRecord],
    csrf_token: &str,
    error: Option<&str>,
    can_edit: bool,
) -> String {
    let collection = collection.clone();
    let cards = cards.to_vec();
    let decks = decks.to_vec();
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let has_cards = !cards.is_empty();
    view! {
        <AppShell title="Collection" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Collection"</p>
                    <h1>{collection.name.clone()}</h1>
                    <p class="lede">{collection.notes.clone()}</p>
                    <nav class="actions" aria-label="Collection actions">
                        <a class="button secondary" href="/collections">"All collections"</a>
                    </nav>
                    <dl class="status-list">
                        <div><dt>"Visibility"</dt><dd>{collection.visibility.clone()}</dd></div>
                    </dl>
                </section>
                <section class="split-layout wide-left">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Cards"</h2>
                            <span>{cards.iter().map(|card| card.quantity).sum::<i32>()} " total"</span>
                        </div>
                        {if has_cards {
                            view! {
                                <div class="list">
                                    {cards.into_iter().map(|card| view! {
                                        <article class="list-item">
                                            <div>
                                                <h2>{card.card_name}</h2>
                                                <p>{card.location}</p>
                                            </div>
                                            <dl class="compact-list inline">
                                                <div><dt>"Qty"</dt><dd>{card.quantity}</dd></div>
                                                <div><dt>"Foil"</dt><dd>{yes_no(card.foil)}</dd></div>
                                                <div><dt>"Condition"</dt><dd>{card.condition}</dd></div>
                                            </dl>
                                        </article>
                                    }).collect_view()}
                                </div>
                            }.into_any()
                        } else {
                            view! { <p class="empty-state">"No cards tracked yet."</p> }.into_any()
                        }}
                    </div>
                    {can_edit.then(|| view! {
                        <form method="post" action=format!("/collections/{}/cards", collection.id) class="form-panel">
                            <h2>"Add cards"</h2>
                            {error.map(|message| view! { <p class="form-error">{message}</p> })}
                            <input type="hidden" name="csrf_token" value=csrf_token/>
                            <label>"Card"<input name="card_name" required placeholder="Sol Ring"/></label>
                            <div class="field-grid">
                                <label>"Set"<input name="set_code" placeholder="cmm"/></label>
                                <label>"Collector #"<input name="collector_number" placeholder="400"/></label>
                            </div>
                            <div class="field-grid">
                                <label>"Quantity"<input name="quantity" inputmode="numeric" value="1"/></label>
                                <label>
                                    "Condition"
                                    <select name="condition">
                                        <option value="unknown">"Unknown"</option>
                                        <option value="mint">"Mint"</option>
                                        <option value="near_mint">"Near mint"</option>
                                        <option value="lightly_played">"Lightly played"</option>
                                        <option value="moderately_played">"Moderately played"</option>
                                        <option value="heavily_played">"Heavily played"</option>
                                        <option value="damaged">"Damaged"</option>
                                    </select>
                                </label>
                            </div>
                            <label>"Location"<input name="location" placeholder="Blue binder"/></label>
                            <label class="checkbox-row">
                                <input type="checkbox" name="foil" value="true"/>
                                "Foil"
                            </label>
                            <button class="button primary" type="submit">"Add card"</button>
                        </form>
                    })}
                </section>
                <section class="workspace-panel section-gap">
                    <div class="section-heading">
                        <h2>"Deck gaps"</h2>
                        <span>{decks.len()} " active decks"</span>
                    </div>
                    {if decks.is_empty() {
                        view! { <p class="empty-state">"Import a decklist to compare it with this collection."</p> }.into_any()
                    } else {
                        view! {
                            <div class="list">
                                {decks.into_iter().map(|deck| view! {
                                    <article class="list-item">
                                        <div>
                                            <h2>{deck.name.clone()}</h2>
                                            <p>{deck.commander}</p>
                                        </div>
                                        <nav class="actions" aria-label="Deck collection actions">
                                            <a class="button secondary" href=format!("/collections/{}/decks/{}/missing", collection.id, deck.id)>"Missing"</a>
                                            <a class="button secondary" href=format!("/collections/{}/decks/{}/proxy-list", collection.id, deck.id)>"Proxy list"</a>
                                        </nav>
                                    </article>
                                }).collect_view()}
                            </div>
                        }.into_any()
                    }}
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_collection_missing_cards(
    collection: &CollectionRecord,
    deck_id: uuid::Uuid,
    cards: &[DeckMissingCardRecord],
) -> String {
    let collection = collection.clone();
    let cards = cards.to_vec();
    let has_cards = !cards.is_empty();

    view! {
        <AppShell title="Missing Cards" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"Missing cards"</p>
                    <h1>{collection.name.clone()}</h1>
                    <nav class="actions" aria-label="Missing card actions">
                        <a class="button secondary" href=format!("/collections/{}", collection.id)>"Collection"</a>
                        <a class="button secondary" href=format!("/collections/{}/decks/{}/proxy-list", collection.id, deck_id)>"Proxy list"</a>
                    </nav>
                </section>
                <section class="workspace-panel">
                    <div class="section-heading">
                        <h2>"Needed"</h2>
                        <span>{cards.len()} " cards"</span>
                    </div>
                    {if has_cards {
                        view! {
                            <div class="list">
                                {cards.into_iter().map(|card| view! {
                                    <article class="list-item">
                                        <div>
                                            <h2>{card.card_name}</h2>
                                            <p>{card.section}</p>
                                        </div>
                                        <dl class="compact-list inline">
                                            <div><dt>"Need"</dt><dd>{card.required_quantity}</dd></div>
                                            <div><dt>"Owned"</dt><dd>{card.owned_quantity}</dd></div>
                                            <div><dt>"Missing"</dt><dd>{card.missing_quantity}</dd></div>
                                        </dl>
                                    </article>
                                }).collect_view()}
                            </div>
                        }.into_any()
                    } else {
                        view! { <p class="empty-state">"This collection covers the latest imported decklist."</p> }.into_any()
                    }}
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_wishlists(
    csrf_token: &str,
    wishlists: &[WishlistRecord],
    playgroups: &[PlaygroupWithRole],
    error: Option<&str>,
    form: Option<&WishlistForm>,
) -> String {
    let csrf_token = csrf_token.to_owned();
    let wishlists = wishlists.to_vec();
    let playgroups = playgroups.to_vec();
    let error = error.map(str::to_owned);
    let name = form.map(|form| form.name.as_str()).unwrap_or("").to_owned();
    let visibility = form
        .map(|form| form.visibility.as_str())
        .unwrap_or("private")
        .to_owned();
    let playgroup_id = form
        .map(|form| form.playgroup_id.as_str())
        .unwrap_or("")
        .to_owned();
    let notes = form
        .map(|form| form.notes.as_str())
        .unwrap_or("")
        .to_owned();
    let has_wishlists = !wishlists.is_empty();

    view! {
        <AppShell title="Wishlists" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"Collection tracking"</p>
                    <h1>"Wishlists"</h1>
                    <nav class="actions" aria-label="Wishlist navigation">
                        <a class="button secondary" href="/collections">"Collections"</a>
                    </nav>
                </section>
                <section class="split-layout wide-left">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Visible wishlists"</h2>
                            <span>{wishlists.len()} " wishlists"</span>
                        </div>
                        {if has_wishlists {
                            view! {
                                <div class="list">
                                    {wishlists.into_iter().map(|wishlist| view! {
                                        <article class="list-item">
                                            <div>
                                                <h2><a href=format!("/wishlists/{}", wishlist.id)>{wishlist.name}</a></h2>
                                                <p>{wishlist.notes}</p>
                                            </div>
                                            <dl class="compact-list inline">
                                                <div><dt>"Visibility"</dt><dd>{wishlist.visibility}</dd></div>
                                            </dl>
                                        </article>
                                    }).collect_view()}
                                </div>
                            }.into_any()
                        } else {
                            view! { <p class="empty-state">"No visible wishlists yet."</p> }.into_any()
                        }}
                    </div>
                    <form method="post" action="/wishlists" class="form-panel">
                        <h2>"New wishlist"</h2>
                        {error.map(|message| view! { <p class="form-error">{message}</p> })}
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>"Name"<input name="name" required value=name/></label>
                        <div class="field-grid">
                            <label>
                                "Visibility"
                                <select name="visibility">
                                    <option value="private" selected=visibility == "private">"Private"</option>
                                    <option value="playgroup" selected=visibility == "playgroup">"Playgroup"</option>
                                    <option value="public" selected=visibility == "public">"Public"</option>
                                </select>
                            </label>
                            <label>
                                "Playgroup"
                                <select name="playgroup_id">
                                    <option value="" selected=playgroup_id.is_empty()>"None"</option>
                                    {playgroups.into_iter().map(|playgroup| {
                                        let id = playgroup.id.to_string();
                                        view! {
                                            <option value=id.clone() selected=playgroup_id == id>
                                                {playgroup.name}
                                            </option>
                                        }
                                    }).collect_view()}
                                </select>
                            </label>
                        </div>
                        <label>"Notes"<textarea name="notes" rows="3">{notes}</textarea></label>
                        <button class="button primary" type="submit">"Save wishlist"</button>
                    </form>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_wishlist_detail(
    wishlist: &WishlistRecord,
    cards: &[WishlistCardRecord],
    collections: &[CollectionRecord],
    csrf_token: &str,
    error: Option<&str>,
    can_edit: bool,
) -> String {
    let wishlist = wishlist.clone();
    let cards = cards.to_vec();
    let collections = collections.to_vec();
    let csrf_token = csrf_token.to_owned();
    let error = error.map(str::to_owned);
    let has_cards = !cards.is_empty();

    view! {
        <AppShell title="Wishlist" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">"Wishlist"</p>
                    <h1>{wishlist.name.clone()}</h1>
                    <p class="lede">{wishlist.notes.clone()}</p>
                    <nav class="actions" aria-label="Wishlist actions">
                        <a class="button secondary" href="/wishlists">"All wishlists"</a>
                        <a class="button secondary" href="/collections">"Collections"</a>
                    </nav>
                    <dl class="status-list">
                        <div><dt>"Visibility"</dt><dd>{wishlist.visibility.clone()}</dd></div>
                    </dl>
                </section>
                <section class="split-layout wide-left">
                    <div class="workspace-panel">
                        <div class="section-heading">
                            <h2>"Cards"</h2>
                            <span>{cards.iter().map(|card| card.desired_quantity).sum::<i32>()} " wanted"</span>
                        </div>
                        {if has_cards {
                            view! {
                                <div class="list">
                                    {cards.into_iter().map(|card| view! {
                                        <article class="list-item">
                                            <div>
                                                <h2>{card.card_name}</h2>
                                                <p>{card.notes}</p>
                                            </div>
                                            <dl class="compact-list inline">
                                                <div><dt>"Qty"</dt><dd>{card.desired_quantity}</dd></div>
                                                <div><dt>"Priority"</dt><dd>{card.priority}</dd></div>
                                            </dl>
                                        </article>
                                    }).collect_view()}
                                </div>
                            }.into_any()
                        } else {
                            view! { <p class="empty-state">"No wishlist cards yet."</p> }.into_any()
                        }}
                    </div>
                    {can_edit.then(|| view! {
                        <form method="post" action=format!("/wishlists/{}/cards", wishlist.id) class="form-panel">
                            <h2>"Add or update card"</h2>
                            {error.map(|message| view! { <p class="form-error">{message}</p> })}
                            <input type="hidden" name="csrf_token" value=csrf_token/>
                            <label>"Card"<input name="card_name" required placeholder="Counterspell"/></label>
                            <div class="field-grid">
                                <label>"Quantity"<input name="desired_quantity" inputmode="numeric" value="1"/></label>
                                <label>
                                    "Priority"
                                    <select name="priority">
                                        <option value="medium">"Medium"</option>
                                        <option value="high">"High"</option>
                                        <option value="low">"Low"</option>
                                    </select>
                                </label>
                            </div>
                            <label>"Notes"<textarea name="notes" rows="3"></textarea></label>
                            <button class="button primary" type="submit">"Save card"</button>
                        </form>
                    })}
                </section>
                <section class="workspace-panel section-gap">
                    <div class="section-heading">
                        <h2>"Collection coverage"</h2>
                        <span>{collections.len()} " visible collections"</span>
                    </div>
                    {if collections.is_empty() {
                        view! { <p class="empty-state">"Create a collection to compare owned cards against this wishlist."</p> }.into_any()
                    } else {
                        view! {
                            <div class="list">
                                {collections.into_iter().map(|collection| view! {
                                    <article class="list-item">
                                        <div>
                                            <h2>{collection.name.clone()}</h2>
                                            <p>{collection.notes}</p>
                                        </div>
                                        <nav class="actions" aria-label="Wishlist collection actions">
                                            <a class="button secondary" href=format!("/wishlists/{}/collections/{}/missing", wishlist.id, collection.id)>"Needed"</a>
                                        </nav>
                                    </article>
                                }).collect_view()}
                            </div>
                        }.into_any()
                    }}
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_wishlist_missing_cards(
    wishlist: &WishlistRecord,
    collection: &CollectionRecord,
    cards: &[WishlistMissingCardRecord],
) -> String {
    let wishlist = wishlist.clone();
    let collection = collection.clone();
    let cards = cards.to_vec();
    let has_cards = !cards.is_empty();

    view! {
        <AppShell title="Wishlist Needed Cards" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"Wishlist needed"</p>
                    <h1>{wishlist.name.clone()}</h1>
                    <p class="lede">{collection.name.clone()}</p>
                    <nav class="actions" aria-label="Wishlist needed actions">
                        <a class="button secondary" href=format!("/wishlists/{}", wishlist.id)>"Wishlist"</a>
                        <a class="button secondary" href=format!("/collections/{}", collection.id)>"Collection"</a>
                    </nav>
                </section>
                <section class="workspace-panel">
                    <div class="section-heading">
                        <h2>"Needed after collection"</h2>
                        <span>{cards.len()} " cards"</span>
                    </div>
                    {if has_cards {
                        view! {
                            <div class="list">
                                {cards.into_iter().map(|card| view! {
                                    <article class="list-item">
                                        <div>
                                            <h2>{card.card_name}</h2>
                                            <p>{card.notes}</p>
                                        </div>
                                        <dl class="compact-list inline">
                                            <div><dt>"Want"</dt><dd>{card.desired_quantity}</dd></div>
                                            <div><dt>"Owned"</dt><dd>{card.owned_quantity}</dd></div>
                                            <div><dt>"Needed"</dt><dd>{card.missing_quantity}</dd></div>
                                            <div><dt>"Priority"</dt><dd>{card.priority}</dd></div>
                                        </dl>
                                    </article>
                                }).collect_view()}
                            </div>
                        }.into_any()
                    } else {
                        view! { <p class="empty-state">"This collection covers the wishlist."</p> }.into_any()
                    }}
                </section>
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
        <AppShell title="New Event" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
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
        <AppShell title="Edit Event" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
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
        <AppShell title="Event" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">{event.playgroup_name.clone()}</p>
                    <h1>{event.title.clone()}</h1>
                    <p class="lede">{display_datetime(event.start_time)}</p>
                    <nav class="actions" aria-label="Event actions">
                        {context.can_edit.then(|| view! { <a class="button primary" href=format!("/events/{}/edit", event.id)>"Edit"</a> })}
                        <a class="button secondary" href=format!("/events/{}/pods", event.id)>"Pods"</a>
                        {public_url.map(|url| view! { <a class="button secondary" href=url>"Public page"</a> })}
                        {invite_url.map(|url| view! { <a class="button ghost" href=url>"Invite RSVP"</a> })}
                    </nav>
                    <p class="body-copy">{event.description.clone()}</p>
                    <LocationBlock location=context.location.clone() show_address=context.show_address/>
                </section>
                <section class="split-layout">
                    <RsvpPanel event_id=event.id csrf_token=csrf_token.clone() user_rsvp=context.user_rsvp.clone()/>
                    <AttendeeList rsvps=context.rsvps/>
                </section>
                <section class="split-layout section-gap">
                    <DeckDeclarationPanel event_id=event.id csrf_token=csrf_token.clone() decks=context.user_decks/>
                    <EventDeckDeclarationList declarations=context.deck_declarations/>
                </section>
                <section class="split-layout section-gap">
                    <GameLogPanel
                        event_id=event.id
                        csrf_token=csrf_token.clone()
                        pods=context.pods
                        can_edit=context.can_edit
                    />
                    <GameHistoryList games=context.games/>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_event_pods(
    event: &EventWithRole,
    pods: &[PodWithSeats],
    csrf_token: &str,
    can_edit: bool,
) -> String {
    let event = event.clone();
    let pods = pods.to_vec();
    let csrf_token = csrf_token.to_owned();
    let pod_options = pods
        .iter()
        .map(|pod| (pod.pod.id, pod.pod.name.clone()))
        .collect::<Vec<_>>();

    view! {
        <AppShell title="Pods" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header">
                    <p class="eyebrow">{event.playgroup_name.clone()}</p>
                    <h1>{event.title.clone()} " pods"</h1>
                    <p class="lede">{display_datetime(event.start_time)}</p>
                    <nav class="actions" aria-label="Pod actions">
                        <a class="button secondary" href=format!("/events/{}", event.id)>"Event"</a>
                        {can_edit.then(|| view! {
                            <form method="post" action=format!("/events/{}/pods/generate", event.id) class="inline-form">
                                <input type="hidden" name="csrf_token" value=csrf_token.clone()/>
                                <button class="button primary" type="submit">"Generate"</button>
                            </form>
                        })}
                        {(can_edit && !pods.is_empty()).then(|| view! {
                            <form method="post" action=format!("/events/{}/pods/publish", event.id) class="inline-form">
                                <input type="hidden" name="csrf_token" value=csrf_token.clone()/>
                                <button class="button secondary" type="submit">"Publish"</button>
                            </form>
                        })}
                    </nav>
                </section>
                {if pods.is_empty() {
                    view! { <p class="empty-state">"No pod assignments yet."</p> }.into_any()
                } else {
                    view! {
                        <section class="pod-grid" aria-label="Pod assignments">
                            {pods.into_iter().map(|pod| {
                                let pod_id = pod.pod.id;
                                let state = pod.pod.state.clone();
                                let pod_name = pod.pod.name.clone();
                                let score = pod.pod.total_score;
                                let options = pod_options.clone();
                                let csrf_for_lock = csrf_token.clone();
                                let csrf_for_seats = csrf_token.clone();
                                view! {
                                    <article class="panel pod-panel">
                                        <div class="section-heading">
                                            <div>
                                                <h2>{pod_name}</h2>
                                                <span>"Score " {score}</span>
                                            </div>
                                            <span class="badge">{state.clone()}</span>
                                        </div>
                                        <dl class="status-list compact-list">
                                            <div><dt>"Size"</dt><dd>{pod.pod.size_fit_score}</dd></div>
                                            <div><dt>"Bracket"</dt><dd>{pod.pod.bracket_compatibility_score}</dd></div>
                                            <div><dt>"Pairs"</dt><dd>{pod.pod.repeat_player_pair_penalty}</dd></div>
                                            <div><dt>"Decks"</dt><dd>{pod.pod.repeat_deck_matchup_penalty}</dd></div>
                                        </dl>
                                        {if pod.seats.is_empty() {
                                            view! { <p class="empty-state">"No seats."</p> }.into_any()
                                        } else {
                                            view! {
                                                <div class="list">
                                                    {pod.seats.into_iter().map(|seat| {
                                                        let label = seat
                                                            .guest_name
                                                            .clone()
                                                            .or_else(|| seat.user_id.map(|id| format!("Member {}", short_id(id))))
                                                            .unwrap_or_else(|| "Seat".to_owned());
                                                        let csrf_for_move = csrf_for_seats.clone();
                                                        view! {
                                                            <article class="list-item">
                                                                <div>
                                                                    <h3>{seat.seat_position} ". " {label}</h3>
                                                                    <p>{seat.deck_id.map(|id| format!("Deck {}", short_id(id))).unwrap_or_else(|| "No deck declared".to_owned())}</p>
                                                                </div>
                                                                {can_edit.then(|| view! {
                                                                    <form method="post" action=format!("/pods/{pod_id}/seats/{}/move", seat.id) class="move-form">
                                                                        <input type="hidden" name="csrf_token" value=csrf_for_move/>
                                                                        <select name="target_pod_id" aria-label="Target pod">
                                                                            {options.iter().map(|(id, name)| view! {
                                                                                <option value=id.to_string() selected=*id == pod_id>{name.clone()}</option>
                                                                            }).collect_view()}
                                                                        </select>
                                                                        <input type="number" min="1" name="seat_position" value=seat.seat_position.to_string() aria-label="Seat"/>
                                                                        <button class="button secondary" type="submit">"Move"</button>
                                                                    </form>
                                                                })}
                                                            </article>
                                                        }
                                                    }).collect_view()}
                                                </div>
                                            }.into_any()
                                        }}
                                        {(can_edit && state == "proposed").then(|| view! {
                                            <form method="post" action=format!("/pods/{pod_id}/lock") class="inline-form">
                                                <input type="hidden" name="csrf_token" value=csrf_for_lock/>
                                                <button class="button secondary" type="submit">"Lock"</button>
                                            </form>
                                        })}
                                    </article>
                                }
                            }).collect_view()}
                        </section>
                    }.into_any()
                }}
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
            <main id="main" class="shell">
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
            <main id="main" class="shell auth-shell">
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
        <AppShell title="Settings" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
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

pub fn render_meta_dashboard(dashboard: &MetaDashboard) -> String {
    let dashboard = dashboard.clone();
    let has_playgroups = !dashboard.attendance.is_empty();

    view! {
        <AppShell title="Meta" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"Meta"</p>
                    <h1>"Meta Dashboard"</h1>
                </section>
                {if has_playgroups {
                    view! {
                        <div class="stack">
                            {dashboard.attendance.iter().map(|group| {
                                let playgroup_id = group.playgroup_id;
                                let deck_win_rates = dashboard
                                    .deck_win_rates
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let player_win_rates = dashboard
                                    .player_win_rates
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let commander_popularity = dashboard
                                    .commander_popularity
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let bracket_distribution = dashboard
                                    .bracket_distribution
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let color_identity_distribution = dashboard
                                    .color_identity_distribution
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let archetype_distribution = dashboard
                                    .archetype_distribution
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let matchup_history = dashboard
                                    .matchup_history
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();
                                let stale_decks = dashboard
                                    .stale_decks
                                    .iter()
                                    .filter(|metric| metric.playgroup_id == playgroup_id)
                                    .cloned()
                                    .collect::<Vec<_>>();

                                view! {
                                    <section class="section-gap">
                                        <div class="section-heading">
                                            <h2>{group.playgroup_name.clone()}</h2>
                                            <span>{group.last_event_at.map(display_datetime).unwrap_or_else(|| "No events".to_owned())}</span>
                                        </div>
                                        <dl class="status-list">
                                            <div><dt>"Events"</dt><dd>{group.events_total}</dd></div>
                                            <div><dt>"Completed"</dt><dd>{group.completed_events}</dd></div>
                                            <div><dt>"Confirmed RSVPs"</dt><dd>{group.confirmed_rsvps}</dd></div>
                                            <div><dt>"Active players"</dt><dd>{group.active_players}</dd></div>
                                            <div><dt>"RSVP yes rate"</dt><dd>{percent_label(group.attendance_rate)}</dd></div>
                                        </dl>
                                        <div class="split-layout section-gap">
                                            <article class="panel">
                                                <div class="section-heading">
                                                    <h2>"Variety"</h2>
                                                    <span>"decks"</span>
                                                </div>
                                                <DistributionList title="Bracket" metrics=bracket_distribution/>
                                                <DistributionList title="Color" metrics=color_identity_distribution/>
                                                <DistributionList title="Archetype" metrics=archetype_distribution/>
                                            </article>
                                            <article class="panel">
                                                <div class="section-heading">
                                                    <h2>"Commanders"</h2>
                                                    <span>"popularity"</span>
                                                </div>
                                                {if commander_popularity.is_empty() {
                                                    view! { <p class="empty-state">"No commander data yet."</p> }.into_any()
                                                } else {
                                                    view! {
                                                        <dl class="compact-list">
                                                            {commander_popularity.into_iter().map(|metric| view! {
                                                                <div>
                                                                    <dt>{metric.commander}</dt>
                                                                    <dd>{format!("{} decks · {} games", metric.deck_count, metric.games_seen)}</dd>
                                                                </div>
                                                            }).collect_view()}
                                                        </dl>
                                                    }.into_any()
                                                }}
                                            </article>
                                        </div>
                                        <div class="split-layout wide-left section-gap">
                                            <article class="panel">
                                                <div class="section-heading">
                                                    <h2>"Planning"</h2>
                                                    <span>"freshness"</span>
                                                </div>
                                                {if matchup_history.is_empty() {
                                                    view! { <p class="empty-state">"No matchup history yet."</p> }.into_any()
                                                } else {
                                                    view! {
                                                        <dl class="compact-list">
                                                            {matchup_history.into_iter().map(|metric| view! {
                                                                <div>
                                                                    <dt>{format!("{}: {}", metric.matchup_type, metric.games_together)}</dt>
                                                                    <dd>{format!("{} vs {} · {}", metric.left_label, metric.right_label, display_datetime(metric.last_played_at))}</dd>
                                                                </div>
                                                            }).collect_view()}
                                                        </dl>
                                                    }.into_any()
                                                }}
                                            </article>
                                            <article class="panel">
                                                <div class="section-heading">
                                                    <h2>"Stale Decks"</h2>
                                                    <span>"rotation"</span>
                                                </div>
                                                {if stale_decks.is_empty() {
                                                    view! { <p class="empty-state">"No stale active decks."</p> }.into_any()
                                                } else {
                                                    view! {
                                                        <dl class="compact-list">
                                                            {stale_decks.into_iter().map(|deck| view! {
                                                                <div>
                                                                    <dt>{deck.deck_name}</dt>
                                                                    <dd>{format!("{} · {}", deck.commander, stale_reason_label(&deck.stale_reason))}</dd>
                                                                </div>
                                                            }).collect_view()}
                                                        </dl>
                                                    }.into_any()
                                                }}
                                            </article>
                                        </div>
                                        <div class="split-layout section-gap">
                                            <article class="panel">
                                                <div class="section-heading">
                                                    <h2>"Deck Wins"</h2>
                                                    <span>"optional ranking"</span>
                                                </div>
                                                {if deck_win_rates.is_empty() {
                                                    view! { <p class="empty-state">"No deck results yet."</p> }.into_any()
                                                } else {
                                                    view! {
                                                        <dl class="compact-list">
                                                            {deck_win_rates.into_iter().map(|metric| view! {
                                                                <div>
                                                                    <dt>{metric.deck_name}</dt>
                                                                    <dd>{format!("{} · {}-{} · {}", metric.commander, metric.wins, metric.games_played, percent_label(metric.win_rate))}</dd>
                                                                </div>
                                                            }).collect_view()}
                                                        </dl>
                                                    }.into_any()
                                                }}
                                            </article>
                                            <article class="panel">
                                                <div class="section-heading">
                                                    <h2>"Player Wins"</h2>
                                                    <span>"optional ranking"</span>
                                                </div>
                                                {if player_win_rates.is_empty() {
                                                    view! { <p class="empty-state">"No player results yet."</p> }.into_any()
                                                } else {
                                                    view! {
                                                        <dl class="compact-list">
                                                            {player_win_rates.into_iter().map(|metric| view! {
                                                                <div>
                                                                    <dt>{metric.display_name}</dt>
                                                                    <dd>{format!("{}-{} · {}", metric.wins, metric.games_played, percent_label(metric.win_rate))}</dd>
                                                                </div>
                                                            }).collect_view()}
                                                        </dl>
                                                    }.into_any()
                                                }}
                                            </article>
                                        </div>
                                    </section>
                                }
                            }).collect_view()}
                        </div>
                    }.into_any()
                } else {
                    view! { <p class="empty-state">"No playgroup meta yet."</p> }.into_any()
                }}
            </main>
        </AppShell>
    }
    .to_html()
}

#[component]
fn DistributionList(title: &'static str, metrics: Vec<MetaDistributionMetric>) -> impl IntoView {
    view! {
        <section class="section-gap">
            <h3>{title}</h3>
            {if metrics.is_empty() {
                view! { <p class="empty-state">"No deck data yet."</p> }.into_any()
            } else {
                view! {
                    <dl class="compact-list">
                        {metrics.into_iter().map(|metric| view! {
                            <div>
                                <dt>{metric.label}</dt>
                                <dd>{metric.deck_count}</dd>
                            </div>
                        }).collect_view()}
                    </dl>
                }.into_any()
            }}
        </section>
    }
}

pub fn render_placeholder(title: &'static str) -> String {
    let (eyebrow, copy) = match title {
        "About" => (
            "Product",
            "Pod Tracker is focused on the real game-night loop: playgroups, event privacy, RSVPs, pod formation, and meta insight.",
        ),
        "Roadmap" => (
            "Build plan",
            "The Rust rewrite is replacing the reference Go surface while preserving the privacy and PostgreSQL-first product boundaries.",
        ),
        "SQL Observatory" => (
            "PostgreSQL",
            "This page will expose safe, scrubbed SQL examples for pairing history, fuzzy card search, reminders, and meta summaries.",
        ),
        _ => (
            "Pod Tracker",
            "This route is reserved for the Rust application surface.",
        ),
    };

    view! {
        <AppShell title=title>
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">{eyebrow}</p>
                    <h1>{title}</h1>
                    <p class="body-copy">{copy}</p>
                </section>
            </main>
        </AppShell>
    }
    .to_html()
}

pub fn render_observatory() -> String {
    let entries = pod_db::observatory_entries();

    view! {
        <AppShell title="SQL Observatory" account_label="Account" account_href="/settings">
            <main id="main" class="shell">
                <section class="page-header compact">
                    <p class="eyebrow">"PostgreSQL"</p>
                    <h1>"SQL Observatory"</h1>
                    <p class="body-copy">
                        "Safe query shapes from the Rust repositories. Inputs are scoped IDs or public card filters; outputs avoid host addresses, contact fields, invite tokens, and private notes."
                    </p>
                </section>
                {entries.iter().copied().map(|entry| view! {
                    <section id=entry.slug class="split-layout wide-left section-gap">
                        <article class="panel">
                            <div class="section-heading">
                                <h2>{entry.title}</h2>
                                <span class="badge">{entry.badge}</span>
                            </div>
                            <pre class="sql-block"><code>{entry.sql}</code></pre>
                        </article>
                        <article class="panel">
                            <h2>"Plan Shape"</h2>
                            <dl class="compact-list">
                                <div><dt>"Source"</dt><dd><code>{entry.source}</code></dd></div>
                                <div><dt>"Inputs"</dt><dd>{entry.inputs}</dd></div>
                                <div><dt>"Indexes"</dt><dd>{entry.indexes}</dd></div>
                                <div><dt>"Plan"</dt><dd>{entry.plan_shape}</dd></div>
                                <div><dt>"Output"</dt><dd>{entry.output}</dd></div>
                                <div><dt>"Sample"</dt><dd>{entry.sample_data}</dd></div>
                            </dl>
                        </article>
                    </section>
                }).collect_view()}
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
fn DeckList(decks: Vec<DeckRecord>) -> impl IntoView {
    view! {
        <div class="list">
            {decks
                .into_iter()
                .map(|deck| {
                    let meta = format!(
                        "{} · {} · {}",
                        deck.commander, deck.color_identity, deck.archetype
                    );
                    view! {
                        <article class="list-item">
                            <div>
                                <h3><a href=format!("/decks/{}", deck.id)>{deck.name}</a></h3>
                                <p>{meta}</p>
                            </div>
                            <span class="badge">{deck.visibility}</span>
                        </article>
                    }
                })
                .collect_view()}
        </div>
    }
}

#[component]
fn DeckDeclarationPanel(
    event_id: uuid::Uuid,
    csrf_token: String,
    decks: Vec<DeckRecord>,
) -> impl IntoView {
    let has_decks = !decks.is_empty();

    view! {
        <form method="post" action=format!("/events/{event_id}/decks") class="form-panel">
            <h2>"Deck declaration"</h2>
            {if has_decks {
                view! {
                    <>
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>
                            "Deck"
                            <select name="deck_id">
                                {decks.into_iter().map(|deck| view! {
                                    <option value=deck.id.to_string()>{deck.name} " - " {deck.commander}</option>
                                }).collect_view()}
                            </select>
                        </label>
                        <label>"Preference"<input type="number" name="preference" min="1" max="5" value="1"/></label>
                        <label>"Testing notes"<textarea name="testing_notes" rows="3"></textarea></label>
                        <button class="button primary" type="submit">"Declare deck"</button>
                    </>
                }.into_any()
            } else {
                view! {
                    <>
                        <p class="empty-state">"No active owned decks available."</p>
                        <a class="button secondary" href="/decks">"Add deck"</a>
                    </>
                }.into_any()
            }}
        </form>
    }
}

#[component]
fn EventDeckDeclarationList(declarations: Vec<EventDeckDeclarationWithDeck>) -> impl IntoView {
    let has_declarations = !declarations.is_empty();

    view! {
        <section class="panel">
            <h2>"Declared decks"</h2>
            {if has_declarations {
                view! {
                    <div class="list">
                        {declarations.into_iter().map(|declaration| {
                            let meta = format!(
                                "{} · {} · preference {}",
                                declaration.commander,
                                declaration.color_identity,
                                declaration.preference
                            );
                            view! {
                                <article class="list-item">
                                    <div>
                                        <h3>{declaration.deck_name}</h3>
                                        <p>{meta}</p>
                                        {(!declaration.testing_notes.is_empty()).then(|| view! { <p>{declaration.testing_notes}</p> })}
                                    </div>
                                    <span class="badge">{declaration.claimed_bracket}</span>
                                </article>
                            }
                        }).collect_view()}
                    </div>
                }.into_any()
            } else {
                view! { <p class="empty-state">"No decks declared yet."</p> }.into_any()
            }}
        </section>
    }
}

#[component]
fn GameLogPanel(
    event_id: uuid::Uuid,
    csrf_token: String,
    pods: Vec<PodWithSeats>,
    can_edit: bool,
) -> impl IntoView {
    let pod_choices = pods
        .iter()
        .filter(|pod| pod.pod.state == "active" || pod.pod.state == "locked")
        .map(|pod| (pod.pod.id, pod.pod.name.clone(), pod.pod.state.clone()))
        .collect::<Vec<_>>();
    let player_choices = pods
        .iter()
        .filter(|pod| pod.pod.state == "active" || pod.pod.state == "locked")
        .flat_map(|pod| {
            pod.seats.iter().filter_map(|seat| {
                seat.user_id.map(|user_id| {
                    let label = seat
                        .guest_name
                        .clone()
                        .unwrap_or_else(|| format!("Member {}", short_id(user_id)));
                    (user_id, format!("{} - {}", pod.pod.name, label))
                })
            })
        })
        .collect::<Vec<_>>();
    let can_log = can_edit && !pod_choices.is_empty();

    view! {
        <form method="post" action=format!("/events/{event_id}/games") class="form-panel">
            <h2>"Log game"</h2>
            {if can_log {
                view! {
                    <>
                        <input type="hidden" name="csrf_token" value=csrf_token/>
                        <label>
                            "Pod"
                            <select name="pod_id">
                                {pod_choices.into_iter().map(|(id, name, state)| view! {
                                    <option value=id.to_string()>{name} " - " {state}</option>
                                }).collect_view()}
                            </select>
                        </label>
                        <label>
                            "Result"
                            <select name="result_type">
                                <option value="normal_win">"Normal win"</option>
                                <option value="combo_win">"Combo win"</option>
                                <option value="combat_win">"Combat win"</option>
                                <option value="concession">"Concession"</option>
                                <option value="draw">"Draw"</option>
                                <option value="time_called">"Time called"</option>
                                <option value="unfinished">"Unfinished"</option>
                                <option value="archenemy_win">"Archenemy win"</option>
                                <option value="team_win">"Team win"</option>
                            </select>
                        </label>
                        <label>
                            "Winner"
                            <select name="winner_user_id">
                                <option value="">"No single winner"</option>
                                {player_choices.iter().map(|(id, label)| view! {
                                    <option value=id.to_string()>{label.clone()}</option>
                                }).collect_view()}
                            </select>
                        </label>
                        <div class="field-grid">
                            <label>"Turns"<input type="number" min="1" name="turn_count"/></label>
                            <label>"Minutes"<input type="number" min="1" name="duration_minutes"/></label>
                        </div>
                        <label>
                            "First player"
                            <select name="first_player_user_id">
                                <option value="">"Not recorded"</option>
                                {player_choices.iter().map(|(id, label)| view! {
                                    <option value=id.to_string()>{label.clone()}</option>
                                }).collect_view()}
                            </select>
                        </label>
                        <div class="field-grid">
                            <label>
                                "First out"
                                <select name="elimination_1_user_id">
                                    <option value="">"Not recorded"</option>
                                    {player_choices.iter().map(|(id, label)| view! {
                                        <option value=id.to_string()>{label.clone()}</option>
                                    }).collect_view()}
                                </select>
                            </label>
                            <label>
                                "Second out"
                                <select name="elimination_2_user_id">
                                    <option value="">"Not recorded"</option>
                                    {player_choices.iter().map(|(id, label)| view! {
                                        <option value=id.to_string()>{label.clone()}</option>
                                    }).collect_view()}
                                </select>
                            </label>
                            <label>
                                "Third out"
                                <select name="elimination_3_user_id">
                                    <option value="">"Not recorded"</option>
                                    {player_choices.iter().map(|(id, label)| view! {
                                        <option value=id.to_string()>{label.clone()}</option>
                                    }).collect_view()}
                                </select>
                            </label>
                            <label>
                                "Fourth out"
                                <select name="elimination_4_user_id">
                                    <option value="">"Not recorded"</option>
                                    {player_choices.iter().map(|(id, label)| view! {
                                        <option value=id.to_string()>{label.clone()}</option>
                                    }).collect_view()}
                                </select>
                            </label>
                            <label>
                                "Fifth out"
                                <select name="elimination_5_user_id">
                                    <option value="">"Not recorded"</option>
                                    {player_choices.iter().map(|(id, label)| view! {
                                        <option value=id.to_string()>{label.clone()}</option>
                                    }).collect_view()}
                                </select>
                            </label>
                        </div>
                        <label>"Team"<input name="winning_team"/></label>
                        <label>"Tags"<input name="tags" placeholder="combo, long game"/></label>
                        <label>"Notes"<textarea name="notes" rows="3"></textarea></label>
                        <label class="checkbox-row">
                            <input type="checkbox" name="complete_event" value="true"/>
                            "Complete event"
                        </label>
                        <button class="button primary" type="submit">"Log game"</button>
                    </>
                }.into_any()
            } else if can_edit {
                view! { <p class="empty-state">"Publish or lock pods before logging games."</p> }.into_any()
            } else {
                view! { <p class="empty-state">"Game logging is limited to hosts and admins."</p> }.into_any()
            }}
        </form>
    }
}

#[component]
fn GameHistoryList(games: Vec<GameWithPlayers>) -> impl IntoView {
    let has_games = !games.is_empty();

    view! {
        <section class="panel">
            <h2>"Game history"</h2>
            {if has_games {
                view! {
                    <div class="list">
                        {games.into_iter().map(|game| {
                            let winner = game
                                .result
                                .winner_user_id
                                .map(|id| format!("Winner {}", short_id(id)))
                                .unwrap_or_else(|| "No single winner".to_owned());
                            let summary = format!(
                                "{} · {} players · {}",
                                result_type_label(&game.game.result_type),
                                game.players.len(),
                                display_datetime(game.game.completed_at)
                            );
                            let mut eliminated = game
                                .players
                                .iter()
                                .filter_map(|player| {
                                    player.elimination_order.map(|order| {
                                        let label = player
                                            .user_id
                                            .map(|id| format!("Member {}", short_id(id)))
                                            .or_else(|| player.guest_name.clone())
                                            .unwrap_or_else(|| "Unknown".to_owned());
                                        (order, label)
                                    })
                                })
                                .collect::<Vec<_>>();
                            eliminated.sort_by_key(|(order, _)| *order);
                            let elimination_summary = (!eliminated.is_empty()).then(|| {
                                eliminated
                                    .into_iter()
                                    .map(|(order, label)| format!("{order}. {label}"))
                                    .collect::<Vec<_>>()
                                    .join(", ")
                            });
                            view! {
                                <article class="list-item">
                                    <div>
                                        <h3>{winner}</h3>
                                        <p>{summary}</p>
                                        {elimination_summary.map(|summary| view! { <p>"Eliminations: " {summary}</p> })}
                                        {(!game.game.notes.is_empty()).then(|| view! { <p>{game.game.notes}</p> })}
                                    </div>
                                    <span class="badge">
                                        {game.game.turn_count.map(|turns| format!("{turns} turns")).unwrap_or_else(|| "logged".to_owned())}
                                    </span>
                                </article>
                            }
                        }).collect_view()}
                    </div>
                }.into_any()
            } else {
                view! { <p class="empty-state">"No games logged yet."</p> }.into_any()
            }}
        </section>
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

fn percent_label(value: i32) -> String {
    format!("{value}%")
}

fn stale_reason_label(value: &str) -> &'static str {
    match value {
        "never_played" => "never played",
        "idle_45_days" => "idle 45 days",
        _ => "stale",
    }
}

fn yes_no(value: bool) -> &'static str {
    if value { "yes" } else { "no" }
}

fn display_color_identity(colors: &[String]) -> String {
    if colors.is_empty() {
        "C".to_owned()
    } else {
        colors.join("")
    }
}

fn display_number(value: f64) -> String {
    if value.fract() == 0.0 {
        format!("{value:.0}")
    } else {
        format!("{value:.1}")
    }
}

fn truncate_text(value: &str, max_chars: usize) -> String {
    let mut output = value.chars().take(max_chars).collect::<String>();
    if value.chars().count() > max_chars {
        output.push_str("...");
    }
    output
}

fn short_id(id: uuid::Uuid) -> String {
    id.to_string().chars().take(8).collect()
}

fn result_type_label(value: &str) -> &'static str {
    match value {
        "normal_win" => "Normal win",
        "combo_win" => "Combo win",
        "combat_win" => "Combat win",
        "concession" => "Concession",
        "draw" => "Draw",
        "time_called" => "Time called",
        "unfinished" => "Unfinished",
        "archenemy_win" => "Archenemy win",
        "team_win" => "Team win",
        _ => "Game",
    }
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
fn AppShell(
    title: &'static str,
    #[prop(default = "Login")] account_label: &'static str,
    #[prop(default = "/login")] account_href: &'static str,
    children: Children,
) -> impl IntoView {
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
                <a class="skip-link" href="#main">"Skip to content"</a>
                <header class="topbar">
                    <a class="brand" href="/">
                        <span class="brand-mark" aria-hidden="true">"PT"</span>
                        <span class="brand-copy">
                            <span>"Pod Tracker"</span>
                            <small>"Commander ops"</small>
                        </span>
                    </a>
                    <nav class="main-nav" aria-label="Main">
                        <a href="/home">"Home"</a>
                        <a href="/playgroups">"Playgroups"</a>
                        <a href="/events">"Events"</a>
                        <a href="/decks">"Decks"</a>
                        <a href="/cards">"Cards"</a>
                        <a href="/collections">"Collections"</a>
                        <a href="/wishlists">"Wishlists"</a>
                        <a href="/meta">"Meta"</a>
                        <a href="/observatory">"Observatory"</a>
                        <a class="nav-login" href=account_href>{account_label}</a>
                    </nav>
                </header>
                {children()}
            </body>
        </html>
    }
}
