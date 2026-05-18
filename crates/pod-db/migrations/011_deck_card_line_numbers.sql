alter table mtg.deck_cards
  add column line_number integer not null default 0;

alter table mtg.deck_cards
  add constraint deck_cards_line_number_nonnegative check (line_number >= 0);

create index deck_cards_version_line_number_idx
  on mtg.deck_cards (deck_version_id, line_number);
