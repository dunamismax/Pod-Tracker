create extension if not exists vector;

create schema if not exists search;

create table search.card_semantic_embeddings (
  model text not null,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  dimensions integer not null,
  embedding vector not null,
  source_text_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (model, oracle_id),
  constraint card_semantic_embeddings_model_not_blank check (length(btrim(model)) > 0),
  constraint card_semantic_embeddings_dimensions_check check (dimensions between 1 and 2000),
  constraint card_semantic_embeddings_vector_dimensions_check check (
    vector_dims(embedding) = dimensions
  ),
  constraint card_semantic_embeddings_source_hash_not_blank check (
    length(btrim(source_text_hash)) > 0
  )
);

create index card_semantic_embeddings_oracle_id_idx
  on search.card_semantic_embeddings (oracle_id);
create index card_semantic_embeddings_model_dimensions_idx
  on search.card_semantic_embeddings (model, dimensions);

create table search.deck_semantic_embeddings (
  model text not null,
  deck_id uuid not null references core.decks (id) on delete cascade,
  dimensions integer not null,
  embedding vector not null,
  source_text_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (model, deck_id),
  constraint deck_semantic_embeddings_model_not_blank check (length(btrim(model)) > 0),
  constraint deck_semantic_embeddings_dimensions_check check (dimensions between 1 and 2000),
  constraint deck_semantic_embeddings_vector_dimensions_check check (
    vector_dims(embedding) = dimensions
  ),
  constraint deck_semantic_embeddings_source_hash_not_blank check (
    length(btrim(source_text_hash)) > 0
  )
);

create index deck_semantic_embeddings_deck_id_idx
  on search.deck_semantic_embeddings (deck_id);
create index deck_semantic_embeddings_model_dimensions_idx
  on search.deck_semantic_embeddings (model, dimensions);

-- Add a model-specific HNSW expression index after choosing a local
-- embedding model and dimension. pgvector requires indexed rows to share
-- one dimension.
--
-- create index card_semantic_embeddings_local_1536_hnsw_idx
--   on search.card_semantic_embeddings
--   using hnsw ((embedding::vector(1536)) vector_cosine_ops)
--   where model = 'local-1536' and dimensions = 1536;
--
-- create index deck_semantic_embeddings_local_1536_hnsw_idx
--   on search.deck_semantic_embeddings
--   using hnsw ((embedding::vector(1536)) vector_cosine_ops)
--   where model = 'local-1536' and dimensions = 1536;
