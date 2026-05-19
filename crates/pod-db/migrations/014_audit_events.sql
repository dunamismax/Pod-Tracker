create schema if not exists audit;

create table audit.audit_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  actor_user_id uuid references core.users (id) on delete set null,
  playgroup_id uuid references core.playgroups (id) on delete set null,
  event_id uuid references core.events (id) on delete set null,
  subject_table text not null,
  subject_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint audit_events_event_type_not_blank check (length(btrim(event_type)) > 0),
  constraint audit_events_subject_table_not_blank check (length(btrim(subject_table)) > 0),
  constraint audit_events_metadata_is_object check (jsonb_typeof(metadata) = 'object')
);

create index audit_events_event_type_time_idx
on audit.audit_events (event_type, occurred_at desc);

create index audit_events_playgroup_time_idx
on audit.audit_events (playgroup_id, occurred_at desc)
where playgroup_id is not null;

create index audit_events_event_time_idx
on audit.audit_events (event_id, occurred_at desc)
where event_id is not null;

create index audit_events_actor_time_idx
on audit.audit_events (actor_user_id, occurred_at desc)
where actor_user_id is not null;

revoke update, delete on audit.audit_events from public;

create or replace function audit.prevent_audit_event_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit.audit_events is append-only';
end;
$$;

create trigger audit_events_append_only
before update or delete on audit.audit_events
for each row execute function audit.prevent_audit_event_mutation();

create or replace function audit.record_event(
  event_type text,
  actor_user_id uuid,
  playgroup_id uuid,
  event_id uuid,
  subject_table text,
  subject_id uuid,
  metadata jsonb
) returns void
language sql
security definer
set search_path = audit, core, public
as $$
  insert into audit.audit_events (
    event_type, actor_user_id, playgroup_id, event_id,
    subject_table, subject_id, metadata
  )
  values (
    event_type, actor_user_id, playgroup_id, event_id,
    subject_table, subject_id, coalesce(metadata, '{}'::jsonb)
  );
$$;

create or replace function audit.trg_auth_user_created()
returns trigger
language plpgsql
as $$
begin
  perform audit.record_event(
    'auth.user_created',
    new.id,
    null,
    null,
    'core.users',
    new.id,
    '{}'::jsonb
  );
  return new;
end;
$$;

create trigger audit_users_created
after insert on core.users
for each row execute function audit.trg_auth_user_created();

create or replace function audit.trg_session_lifecycle()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    perform audit.record_event(
      'auth.session_created',
      new.user_id,
      null,
      null,
      'core.sessions',
      new.id,
      '{}'::jsonb
    );
    return new;
  end if;

  if old.revoked_at is null and new.revoked_at is not null then
    perform audit.record_event(
      'auth.session_revoked',
      new.user_id,
      null,
      null,
      'core.sessions',
      new.id,
      '{}'::jsonb
    );
  end if;
  return new;
end;
$$;

create trigger audit_sessions_created
after insert on core.sessions
for each row execute function audit.trg_session_lifecycle();

create trigger audit_sessions_revoked
after update of revoked_at on core.sessions
for each row execute function audit.trg_session_lifecycle();

create or replace function audit.trg_membership_changed()
returns trigger
language plpgsql
as $$
declare
  row_value record;
begin
  row_value := case when tg_op = 'DELETE' then old else new end;

  perform audit.record_event(
    case
      when tg_op = 'INSERT' then 'membership.created'
      when tg_op = 'UPDATE' then 'membership.updated'
      else 'membership.deleted'
    end,
    row_value.user_id,
    row_value.playgroup_id,
    null,
    'core.playgroup_memberships',
    row_value.id,
    jsonb_build_object('role', row_value.role, 'operation', lower(tg_op))
  );

  return row_value;
end;
$$;

create trigger audit_memberships_changed
after insert or update or delete on core.playgroup_memberships
for each row execute function audit.trg_membership_changed();

create or replace function audit.trg_invite_changed()
returns trigger
language plpgsql
as $$
declare
  row_value record;
begin
  row_value := case when tg_op = 'DELETE' then old else new end;

  perform audit.record_event(
    case
      when tg_op = 'INSERT' then 'invite.created'
      when tg_op = 'UPDATE' and old.revoked_at is null and new.revoked_at is not null then 'invite.revoked'
      when tg_op = 'UPDATE' then 'invite.updated'
      else 'invite.deleted'
    end,
    row_value.created_by,
    row_value.playgroup_id,
    null,
    'core.playgroup_invites',
    row_value.id,
    jsonb_build_object(
      'role', row_value.role,
      'max_uses_present', row_value.max_uses is not null,
      'expires_at_present', row_value.expires_at is not null,
      'revoked', row_value.revoked_at is not null,
      'used_count', row_value.used_count
    )
  );

  return row_value;
end;
$$;

create trigger audit_invites_changed
after insert or update or delete on core.playgroup_invites
for each row execute function audit.trg_invite_changed();

create or replace function audit.trg_event_changed()
returns trigger
language plpgsql
as $$
declare
  row_value record;
begin
  row_value := case when tg_op = 'DELETE' then old else new end;

  perform audit.record_event(
    case
      when tg_op = 'INSERT' then 'event.created'
      when tg_op = 'UPDATE' and old.completed_at is null and new.completed_at is not null then 'event.completed'
      when tg_op = 'UPDATE' then 'event.updated'
      else 'event.deleted'
    end,
    row_value.created_by,
    row_value.playgroup_id,
    row_value.id,
    'core.events',
    row_value.id,
    jsonb_build_object(
      'visibility', row_value.visibility,
      'has_location', row_value.location_id is not null,
      'completed', row_value.completed_at is not null
    )
  );

  return row_value;
end;
$$;

create trigger audit_events_changed
after insert or update or delete on core.events
for each row execute function audit.trg_event_changed();

create or replace function audit.trg_rsvp_changed()
returns trigger
language plpgsql
as $$
declare
  row_value record;
  event_playgroup_id uuid;
begin
  row_value := case when tg_op = 'DELETE' then old else new end;

  select playgroup_id into event_playgroup_id
  from core.events
  where id = row_value.event_id;

  perform audit.record_event(
    case
      when tg_op = 'INSERT' then 'rsvp.created'
      when tg_op = 'UPDATE' then 'rsvp.updated'
      else 'rsvp.deleted'
    end,
    row_value.user_id,
    event_playgroup_id,
    row_value.event_id,
    'core.event_rsvps',
    row_value.id,
    jsonb_build_object(
      'status', row_value.status,
      'guest_scope', row_value.user_id is null,
      'guest_count', row_value.guest_count
    )
  );

  return row_value;
end;
$$;

create trigger audit_rsvps_changed
after insert or update or delete on core.event_rsvps
for each row execute function audit.trg_rsvp_changed();

create or replace function audit.trg_pod_changed()
returns trigger
language plpgsql
as $$
declare
  row_value record;
  event_playgroup_id uuid;
begin
  row_value := case when tg_op = 'DELETE' then old else new end;

  select playgroup_id into event_playgroup_id
  from core.events
  where id = row_value.event_id;

  perform audit.record_event(
    case
      when tg_op = 'INSERT' then 'pod.created'
      when tg_op = 'UPDATE' and old.state is distinct from new.state then 'pod.state_changed'
      when tg_op = 'UPDATE' then 'pod.updated'
      else 'pod.deleted'
    end,
    null,
    event_playgroup_id,
    row_value.event_id,
    'core.pods',
    row_value.id,
    jsonb_build_object(
      'state', row_value.state,
      'position', row_value.position,
      'total_score', row_value.total_score,
      'published', row_value.published_at is not null
    )
  );

  return row_value;
end;
$$;

create trigger audit_pods_changed
after insert or update or delete on core.pods
for each row execute function audit.trg_pod_changed();

create or replace function audit.trg_result_changed()
returns trigger
language plpgsql
as $$
declare
  row_value record;
  game_event_id uuid;
  event_playgroup_id uuid;
  game_logger_id uuid;
begin
  row_value := case when tg_op = 'DELETE' then old else new end;

  select g.event_id, e.playgroup_id, g.logged_by_user_id
    into game_event_id, event_playgroup_id, game_logger_id
  from core.games g
  join core.events e on e.id = g.event_id
  where g.id = row_value.game_id;

  perform audit.record_event(
    case
      when tg_op = 'INSERT' then 'result.created'
      when tg_op = 'UPDATE' then 'result.updated'
      else 'result.deleted'
    end,
    game_logger_id,
    event_playgroup_id,
    game_event_id,
    'core.game_results',
    row_value.id,
    jsonb_build_object(
      'game_id', row_value.game_id,
      'result_type', row_value.result_type,
      'winner_user_id', row_value.winner_user_id,
      'winning_deck_id', row_value.winning_deck_id,
      'winning_team_present', row_value.winning_team is not null
    )
  );

  return row_value;
end;
$$;

create trigger audit_results_changed
after insert or update or delete on core.game_results
for each row execute function audit.trg_result_changed();
