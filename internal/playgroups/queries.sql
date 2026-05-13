-- name: CreatePlaygroup :one
insert into core.playgroups (name, slug, description, created_by)
values ($1, $2, $3, $4)
returning id, name, slug, description, created_by, created_at, updated_at;

-- name: CreateDefaultPlaygroupSettings :exec
insert into core.playgroup_settings (playgroup_id)
values ($1);

-- name: CreatePlaygroupMembership :exec
insert into core.playgroup_memberships (playgroup_id, user_id, role)
values ($1, $2, $3);

-- name: ListPlaygroupsForUser :many
select
  p.id,
  p.name,
  p.slug,
  p.description,
  m.role
from core.playgroups p
join core.playgroup_memberships m on m.playgroup_id = p.id
where m.user_id = $1
order by p.name;
