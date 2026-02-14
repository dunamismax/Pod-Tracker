import { db } from './db.server';

export type PodSummary = {
  id: number;
  name: string;
  description: string | null;
  role: string;
};

export type EventSummary = {
  id: number;
  podName: string;
  title: string;
  location: string | null;
  scheduledFor: string;
};

export async function listPodsForUser(userId: number): Promise<PodSummary[]> {
  const result = await db.query<PodSummary>(
    `
      select
        p.id,
        p.name,
        p.description,
        pm.role
      from pod_members pm
      inner join pods p on p.id = pm.pod_id
      where pm.user_id = $1
      order by p.created_at desc
    `,
    [userId]
  );

  return result.rows;
}

export async function createPodForUser(
  userId: number,
  name: string,
  description: string | null
): Promise<PodSummary> {
  const client = await db.connect();

  try {
    await client.query('begin');

    const podResult = await client.query<{ id: number; name: string; description: string | null }>(
      `
        insert into pods (name, description, owner_id)
        values ($1, $2, $3)
        returning id, name, description
      `,
      [name, description, userId]
    );

    const pod = podResult.rows[0];

    await client.query(
      `
        insert into pod_members (pod_id, user_id, role)
        values ($1, $2, 'owner')
      `,
      [pod.id, userId]
    );

    await client.query('commit');

    return {
      ...pod,
      role: 'owner',
    };
  } catch (error) {
    await client.query('rollback');
    throw error;
  } finally {
    client.release();
  }
}

export async function listUpcomingEventsForUser(userId: number): Promise<EventSummary[]> {
  const result = await db.query<EventSummary>(
    `
      select
        e.id,
        p.name as "podName",
        e.title,
        e.location,
        e.scheduled_for as "scheduledFor"
      from pod_members pm
      inner join pods p on p.id = pm.pod_id
      inner join events e on e.pod_id = p.id
      where pm.user_id = $1
        and e.scheduled_for >= now() - interval '1 day'
      order by e.scheduled_for asc
      limit 20
    `,
    [userId]
  );

  return result.rows;
}
