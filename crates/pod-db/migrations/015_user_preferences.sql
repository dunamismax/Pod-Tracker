alter table core.users
  add column locale text not null default 'en-US',
  add column timezone text not null default 'UTC',
  add column date_time_format text not null default 'locale_default',
  add constraint users_locale_supported check (locale in ('en-US')),
  add constraint users_timezone_supported check (
    timezone in (
      'UTC',
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Phoenix',
      'America/Los_Angeles',
      'Europe/London',
      'Europe/Paris'
    )
  ),
  add constraint users_date_time_format_supported check (
    date_time_format in ('locale_default', 'iso_24h')
  );
