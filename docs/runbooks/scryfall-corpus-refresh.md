# Scryfall Card Corpus Refresh

Operator runbook for the daily Scryfall card-corpus refresh. Card facts and Commander legality must come from deterministic source data; this job is the canonical pipe that brings Scryfall's bulk data into the production database.

## What it does

`Scryfall::CardCorpusRefreshJob` (`app/jobs/scryfall/card_corpus_refresh_job.rb`) wraps `Scryfall::BulkImporter#import!`. On every run it:

1. Calls Scryfall's public bulk-data index (`https://api.scryfall.com/bulk-data`) and resolves the requested bulk type. The default is `default_cards`.
2. Creates a `CardCorpusRefresh` row in `pending` state, stamping `source_uri`, `content_type`, `content_length`, `scryfall_updated_at`, and the raw bulk-data payload.
3. Marks the row `running`, then streams the bulk JSON array, upserting `CardSet`, `OracleCard`, and `CardPrinting` rows for each `card` object inside a single transaction.
4. Marks the row `succeeded` with object / set / oracle / printing counts when the stream finishes.
5. Marks the row `failed` (with `error_code` + `error_message`) and re-raises if anything inside the transaction blows up.

The Scryfall HTTP client throttles to one request every ~110 ms (Scryfall asks for <10 req/s) and surfaces `429 Too Many Requests` as `Scryfall::Client::RateLimitedError`. The job retries:

- `RateLimitedError` up to 5 times with `30 + n * 30s` backoff.
- `Scryfall::Client::Error` up to 3 times with `30 + n * 60s` backoff.

`ActiveJob::DeserializationError` is discarded (a stale enqueue is not worth retrying).

The job touches `oracle_cards`, `card_sets`, and `card_printings` only. It does not refresh the Commander legality snapshot — that's a separate, intentionally manual import (`Commander_format::LegalitySnapshotImporter`, sourced from `db/seeds/commander/legality_snapshots/current.json`).

## Schedule

Configured in `config/recurring.yml`:

```yaml
production:
  scryfall_card_corpus_refresh:
    class: Scryfall::CardCorpusRefreshJob
    queue: card_corpus
    schedule: every day at 10:30 UTC
```

Solid Queue runs in-Puma (`SOLID_QUEUE_IN_PUMA=true`), so the recurring schedule fires from the `pod-tracker-web.service` process. Restarting the service is enough to pick up changes to `config/recurring.yml`.

10:30 UTC was chosen to land after Scryfall's daily bulk file rotates (Scryfall regenerates `default_cards` at roughly 09:00 UTC) and before North-American evening usage.

## Manual run

Trigger an out-of-band refresh from the production VM (e.g. after a Scryfall bulk regeneration that has fixed a card you need now):

```sh
sudo -u sawyer bin/rails runner 'Scryfall::CardCorpusRefreshJob.perform_now'
```

This blocks until the import finishes — the bulk file is several hundred megabytes and the upsert pass takes a few minutes. Use `perform_later` (or restart the web service) if you'd rather let the in-Puma worker pick it up:

```sh
sudo -u sawyer bin/rails runner 'Scryfall::CardCorpusRefreshJob.perform_later'
```

To refresh a non-default bulk type (e.g. `oracle_cards` for a smaller sanity run):

```sh
sudo -u sawyer bin/rails runner 'Scryfall::CardCorpusRefreshJob.perform_now(bulk_type: "oracle_cards")'
```

## Monitoring

Every run leaves a trail in `card_corpus_refreshes`:

```sh
sudo -u sawyer bin/rails runner '
  CardCorpusRefresh.order(created_at: :desc).limit(5).each do |r|
    puts [r.created_at.iso8601, r.bulk_type, r.status, r.object_count, r.error_code].compact.join(" ")
  end
'
```

A healthy daily entry looks like:

```
2026-05-07T10:30:14Z default_cards succeeded 92341
```

A failed entry preserves `error_code` (`Scryfall::Client::RateLimitedError`, `Scryfall::Client::Error`, `PG::*`, etc.) and `error_message`. Solid Queue keeps its own retry trail in `solid_queue_failed_executions`; combine the two when triaging.

Live job log:

```sh
sudo journalctl -u pod-tracker-web -f --grep 'Scryfall::CardCorpusRefreshJob'
```

## Failure modes

- **`Scryfall::Client::RateLimitedError`** — Scryfall returned 429. The job retries up to 5 times. If it still fails, manually re-run the next day; do not loop the job by hand against a 429 response.
- **`Scryfall::Client::Error: HTTP 503`** — Scryfall is degraded. Retries handle most cases; if the daily run fails, wait for Scryfall to recover and run manually.
- **Network timeout / partial body** — the streaming reader will raise; the in-flight transaction rolls back, so the database stays at the previous corpus. Re-run manually once connectivity is restored.
- **`PG::DiskFull` / migration drift** — the upsert transaction can be large. If the database is short on disk, free space (`bin/backup_db` retention prune, vacuum) and re-run. Schema drift between code and the upsert mappers (`Scryfall::CardNormalizer`) is loud — do not paper over with `rescue`.
- **Bulk type missing** — `Scryfall::Client#bulk_data_object` raises `Scryfall::Client::Error: Scryfall bulk data type not found` if Scryfall renames the bulk file. Check Scryfall's `/bulk-data` index for the new type name and update `Scryfall::BulkImporter::DEFAULT_BULK_TYPE` (or pass the new name to the job) — do not silently switch types.

## Related, deliberately separate

- **Commander legality snapshot** is _not_ refreshed by this job. The banlist + Game Changers list lives at `db/seeds/commander/legality_snapshots/current.json` and is bumped by hand on a published Wizards / Commander RC update; re-import with:
  ```sh
  sudo -u sawyer bin/rails runner 'CommanderFormat::LegalitySnapshotImporter.new.import!'
  ```
  See `app/services/commander_format/legality_snapshot_importer.rb`.
- **Two-card combo catalog** lives at `db/seeds/commander/brackets/two_card_combos.json` and is similarly manual.

The scheduled job is intentionally narrow: it refreshes mechanical card facts. Everything that requires editorial judgment (legality calls, Game Changers categories, MLD/extra-turn overrides, salt/friction overrides) stays under source control and ships with the codebase.

## Verifying after a refresh

```sh
sudo -u sawyer bin/rails runner '
  puts "oracle_cards:   #{OracleCard.count}"
  puts "card_printings: #{CardPrinting.count}"
  puts "card_sets:      #{CardSet.count}"
  puts "latest refresh: #{CardCorpusRefresh.order(:created_at).last&.attributes&.slice("status","object_count","scryfall_updated_at","completed_at")}"
'
```

Expect `oracle_cards` and `card_printings` to grow monotonically over time; `card_sets` grows when WotC ships a new set. A run that succeeded with `object_count` significantly below the prior run is suspicious — Scryfall's `default_cards` does not shrink under normal operations.

## When to re-check Scryfall externally

Per the "External Sources" list in `AGENTS.md`, Scryfall asks for <10 req/s and bulk data for large workloads. Re-check those terms (and the bulk file naming under `/bulk-data`) before changing the importer or scheduling more than one refresh per day.
