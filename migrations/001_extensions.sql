-- +goose Up
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists pg_stat_statements;
create extension if not exists btree_gin;

-- +goose Down
drop extension if exists btree_gin;
drop extension if exists pg_stat_statements;
drop extension if exists pg_trgm;
drop extension if exists pgcrypto;
