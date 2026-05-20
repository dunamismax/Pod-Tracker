alter table mtg.card_printings
  add column printed_name text,
  add column printed_type_line text,
  add column printed_text text;

alter table mtg.card_faces
  add column printed_name text,
  add column printed_type_line text,
  add column printed_text text;

alter table search.card_documents
  add column lang text not null default 'en',
  add column printed_name text,
  add column normalized_printed_name text,
  add column printed_type_line text,
  add column printed_text text,
  add column printed_document tsvector not null default ''::tsvector;

update mtg.card_printings
set printed_name = nullif(raw_payload->>'printed_name', ''),
    printed_type_line = nullif(raw_payload->>'printed_type_line', ''),
    printed_text = nullif(raw_payload->>'printed_text', '');

with printed_faces as (
  select
    p.scryfall_id,
    (face.ordinality - 1)::integer as face_index,
    nullif(face.value->>'printed_name', '') as printed_name,
    nullif(face.value->>'printed_type_line', '') as printed_type_line,
    nullif(face.value->>'printed_text', '') as printed_text
  from mtg.card_printings p,
    lateral jsonb_array_elements(coalesce(p.raw_payload->'card_faces', '[]'::jsonb))
      with ordinality as face(value, ordinality)
)
update mtg.card_faces f
set printed_name = pf.printed_name,
    printed_type_line = pf.printed_type_line,
    printed_text = pf.printed_text
from printed_faces pf
where pf.scryfall_id = f.scryfall_id
  and pf.face_index = f.face_index;

update mtg.card_faces f
set printed_name = p.printed_name,
    printed_type_line = p.printed_type_line,
    printed_text = p.printed_text
from mtg.card_printings p
where p.scryfall_id = f.scryfall_id
  and f.face_index = 0
  and jsonb_array_length(coalesce(p.raw_payload->'card_faces', '[]'::jsonb)) = 0;

update search.card_documents d
set lang = p.lang,
    printed_name = p.printed_name,
    normalized_printed_name = nullif(
      regexp_replace(lower(coalesce(p.printed_name, '')), '[^[:alnum:]]+', '', 'g'),
      ''
    ),
    printed_type_line = p.printed_type_line,
    printed_text = p.printed_text,
    printed_document =
      setweight(to_tsvector('simple', coalesce(p.printed_name, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(p.printed_type_line, '')), 'B') ||
      setweight(to_tsvector('simple', coalesce(p.printed_text, '')), 'C')
from mtg.card_printings p
where p.scryfall_id = d.scryfall_id;

alter table mtg.deck_cards
  drop constraint deck_cards_match_method_check;

alter table mtg.deck_cards
  add constraint deck_cards_match_method_check check (
    match_method in (
      '',
      'exact',
      'normalized',
      'fuzzy',
      'printed_exact',
      'printed_normalized',
      'printed_fuzzy'
    )
  );

create index card_printings_lang_idx on mtg.card_printings (lang);
create index card_printings_printed_name_trgm_idx
  on mtg.card_printings using gin (printed_name gin_trgm_ops)
  where printed_name is not null;
create index card_faces_printed_name_trgm_idx
  on mtg.card_faces using gin (printed_name gin_trgm_ops)
  where printed_name is not null;
create index card_documents_lang_idx on search.card_documents (lang);
create index card_documents_printed_document_gin_idx
  on search.card_documents using gin (printed_document);
create index card_documents_printed_name_trgm_idx
  on search.card_documents using gin (printed_name gin_trgm_ops)
  where printed_name is not null;
create index card_documents_normalized_printed_name_trgm_idx
  on search.card_documents using gin (normalized_printed_name gin_trgm_ops)
  where normalized_printed_name is not null;
