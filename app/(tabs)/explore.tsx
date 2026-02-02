import { useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { ActivityIndicator, Appbar, Button, Card, List, Surface, Text } from 'react-native-paper';

import { useUpcomingEvents } from '@/features/events/events-queries';
import { usePodsByUser } from '@/features/pods/pods-queries';
import { useSupabaseSession } from '@/hooks/use-supabase-session';

const roleLabels = {
  owner: 'Owner',
  admin: 'Admin',
  member: 'Member',
} as const;

function formatEventTime(startsAt: string) {
  const start = new Date(startsAt);
  const dateLabel = new Intl.DateTimeFormat('en-US', { weekday: 'short' }).format(start);
  const timeLabel = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  }).format(start);

  return `${dateLabel} · ${timeLabel}`;
}

export default function ExploreScreen() {
  const { user, isLoading: authLoading } = useSupabaseSession();
  const podsQuery = usePodsByUser(user?.id);
  const podIds = useMemo(() => podsQuery.data?.map((pod) => pod.id) ?? [], [podsQuery.data]);
  const podNameById = useMemo(
    () => new Map((podsQuery.data ?? []).map((pod) => [pod.id, pod.name])),
    [podsQuery.data]
  );
  const eventsQuery = useUpcomingEvents(podIds);
  const isLoading = authLoading || podsQuery.isLoading || eventsQuery.isLoading;
  const pods = podsQuery.data ?? [];
  const upcoming = eventsQuery.data ?? [];

  return (
    <View style={styles.screen}>
      <Appbar.Header elevated>
        <Appbar.Content title="Pods" subtitle="Your trusted circles" />
        <Appbar.Action icon="magnify" onPress={() => undefined} />
      </Appbar.Header>
      <ScrollView contentContainerStyle={styles.content}>
        <Card mode="outlined" style={styles.card}>
          <Card.Title title="Create a new pod" subtitle="Invite your regular crew in minutes." />
          <Card.Content>
            <Text variant="bodyMedium">
              Gatherer keeps coordination scoped to each meet-up. No feeds, no noise.
            </Text>
          </Card.Content>
          <Card.Actions style={styles.cardActions}>
            <Button mode="contained" icon="plus" onPress={() => undefined}>
              New pod
            </Button>
            <Button mode="outlined" icon="qrcode-scan" onPress={() => undefined}>
              Join with code
            </Button>
          </Card.Actions>
        </Card>

        <Surface elevation={1} style={styles.surface}>
          <Text variant="titleMedium">Your pods</Text>
          {isLoading ? (
            <ActivityIndicator />
          ) : !user ? (
            <Text variant="bodyMedium">Sign in to view your pods.</Text>
          ) : pods.length === 0 ? (
            <Text variant="bodyMedium">No pods yet. Create one to get started.</Text>
          ) : (
            pods.map((pod) => (
              <List.Item
                key={pod.id}
                title={pod.name}
                description={
                  [pod.location_text, roleLabels[pod.role] ?? 'Member'].filter(Boolean).join(' · ')
                }
                left={(props) => <List.Icon {...props} icon="account-group" />}
              />
            ))
          )}
        </Surface>

        <Surface elevation={1} style={styles.surface}>
          <Text variant="titleMedium">Upcoming across pods</Text>
          {isLoading ? (
            <ActivityIndicator />
          ) : !user ? (
            <Text variant="bodyMedium">Sign in to see upcoming events.</Text>
          ) : upcoming.length === 0 ? (
            <Text variant="bodyMedium">No upcoming events yet.</Text>
          ) : (
            upcoming.map((event) => (
              <List.Item
                key={event.id}
                title={event.title}
                description={`${formatEventTime(event.starts_at)} · ${
                  podNameById.get(event.pod_id) ?? 'Your pod'
                }`}
                left={(props) => <List.Icon {...props} icon="calendar-star" />}
              />
            ))
          )}
          <Button mode="text" onPress={() => undefined}>
            See all events
          </Button>
        </Surface>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  content: {
    padding: 20,
    gap: 20,
  },
  card: {
    borderRadius: 16,
  },
  cardActions: {
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  surface: {
    padding: 16,
    borderRadius: 16,
    gap: 12,
  },
  listMeta: {
    alignSelf: 'center',
    opacity: 0.7,
  },
});
