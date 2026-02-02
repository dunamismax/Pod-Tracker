import { useMemo } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import {
  ActivityIndicator,
  Appbar,
  Avatar,
  Button,
  Card,
  Chip,
  Divider,
  List,
  Surface,
  Text,
  useTheme,
} from 'react-native-paper';

import { useEventAttendance, useEventChecklist, useUpcomingEvents } from '@/features/events/events-queries';
import { usePodsByUser } from '@/features/pods/pods-queries';
import { useSupabaseSession } from '@/hooks/use-supabase-session';

const arrivalLabels = {
  not_sure: 'Not sure',
  on_the_way: 'On the way',
  arrived: 'Arrived',
  late: 'Running late',
} as const;

const checklistIconByState = {
  open: 'checkbox-blank-circle-outline',
  done: 'checkbox-marked-circle-outline',
  blocked: 'alert-circle-outline',
} as const;

function formatMemberLabel(userId: string) {
  return `Member ${userId.slice(0, 4).toUpperCase()}`;
}

function formatEventTime(startsAt: string, endsAt?: string | null) {
  const start = new Date(startsAt);
  const dateLabel = new Intl.DateTimeFormat('en-US', { weekday: 'short' }).format(start);
  const timeLabel = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  }).format(start);

  if (!endsAt) {
    return `${dateLabel} · ${timeLabel}`;
  }

  const end = new Date(endsAt);
  const endTime = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  }).format(end);

  return `${dateLabel} · ${timeLabel}–${endTime}`;
}

export default function HomeScreen() {
  const theme = useTheme();
  const { user, isLoading: authLoading } = useSupabaseSession();
  const podsQuery = usePodsByUser(user?.id);
  const podIds = useMemo(() => podsQuery.data?.map((pod) => pod.id) ?? [], [podsQuery.data]);
  const podNameById = useMemo(
    () => new Map((podsQuery.data ?? []).map((pod) => [pod.id, pod.name])),
    [podsQuery.data]
  );
  const eventsQuery = useUpcomingEvents(podIds);
  const nextEvent = eventsQuery.data?.[0];
  const attendanceQuery = useEventAttendance(nextEvent?.id);
  const checklistQuery = useEventChecklist(nextEvent?.id);

  const nextEventDisplay = nextEvent
    ? {
        title: nextEvent.title,
        pod: podNameById.get(nextEvent.pod_id) ?? 'Your pod',
        time: formatEventTime(nextEvent.starts_at, nextEvent.ends_at),
        location: nextEvent.location_text ?? 'Location TBD',
      }
    : null;

  const arrivalBoard = (attendanceQuery.data ?? []).map((member) => ({
    name: formatMemberLabel(member.user_id),
    status: arrivalLabels[member.arrival] ?? 'Not sure',
    eta:
      member.arrival === 'arrived'
        ? 'Here'
        : member.eta_minutes
          ? `${member.eta_minutes} min`
          : '—',
  }));

  const checklist = (checklistQuery.data ?? []).map((item) => ({
    label: item.label,
    detail: item.note ?? item.state.replace('_', ' '),
    icon: checklistIconByState[item.state] ?? checklistIconByState.open,
  }));

  const isCoreLoading = authLoading || podsQuery.isLoading || eventsQuery.isLoading;
  const canRespond = Boolean(user && nextEvent);

  return (
    <View style={styles.screen}>
      <Appbar.Header elevated>
        <Appbar.Content title="Gatherer" subtitle="Your next meet-up" />
        <Appbar.Action icon="bell-outline" onPress={() => undefined} />
        <Appbar.Action icon="account-circle" onPress={() => undefined} />
      </Appbar.Header>
      <ScrollView contentContainerStyle={styles.content}>
        <Text variant="titleLarge">Next gather</Text>
        <Card mode="outlined" style={styles.card}>
          <Card.Title
            title={nextEventDisplay?.title ?? 'No upcoming events'}
            subtitle={nextEventDisplay?.pod ?? 'Create a pod event to get started'}
            left={(props) => <Avatar.Text {...props} label="GN" />}
          />
          <Card.Content>
            {isCoreLoading ? (
              <ActivityIndicator />
            ) : !user ? (
              <Text variant="bodyMedium">
                Sign in to see your upcoming gatherings and live arrivals.
              </Text>
            ) : nextEventDisplay ? (
              <List.Item
                title={nextEventDisplay.time}
                description={nextEventDisplay.location}
                left={(props) => <List.Icon {...props} icon="calendar-clock" />}
              />
            ) : (
              <Text variant="bodyMedium">No events scheduled yet.</Text>
            )}
          </Card.Content>
          <Card.Actions style={styles.cardActions}>
            <Button mode="outlined" disabled={!canRespond} onPress={() => undefined}>
              Can&apos;t make it
            </Button>
            <Button mode="contained" disabled={!canRespond} onPress={() => undefined}>
              I&apos;m in
            </Button>
          </Card.Actions>
        </Card>

        <Surface elevation={1} style={styles.surface}>
          <View style={styles.sectionHeader}>
            <Text variant="titleMedium">Arrival board</Text>
            <Chip compact mode="outlined" textStyle={{ color: theme.colors.onSurfaceVariant }}>
              Live ETA
            </Chip>
          </View>
          <Divider style={styles.divider} />
          {authLoading ? (
            <ActivityIndicator />
          ) : !user ? (
            <Text variant="bodyMedium">Sign in to see live arrival updates.</Text>
          ) : attendanceQuery.isLoading ? (
            <ActivityIndicator />
          ) : !nextEvent ? (
            <Text variant="bodyMedium">No active event to track yet.</Text>
          ) : arrivalBoard.length === 0 ? (
            <Text variant="bodyMedium">No arrivals shared yet.</Text>
          ) : (
            arrivalBoard.map((member) => (
              <View key={member.name} style={styles.arrivalRow}>
                <Avatar.Text size={36} label={member.name.slice(0, 2).toUpperCase()} />
                <View style={styles.arrivalMeta}>
                  <Text variant="bodyLarge">{member.name}</Text>
                  <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                    {member.status}
                  </Text>
                </View>
                <Chip compact mode="outlined">
                  {member.eta}
                </Chip>
              </View>
            ))
          )}
        </Surface>

        <Surface elevation={1} style={styles.surface}>
          <Text variant="titleMedium">Checklist</Text>
          <Text variant="bodySmall" style={styles.sectionCaption}>
            Shared prep for tonight&apos;s session.
          </Text>
          {authLoading ? (
            <ActivityIndicator />
          ) : !user ? (
            <Text variant="bodyMedium">Sign in to view shared prep items.</Text>
          ) : checklistQuery.isLoading ? (
            <ActivityIndicator />
          ) : !nextEvent ? (
            <Text variant="bodyMedium">No event checklist yet.</Text>
          ) : checklist.length === 0 ? (
            <Text variant="bodyMedium">Checklist is empty.</Text>
          ) : (
            checklist.map((item) => (
              <List.Item
                key={item.label}
                title={item.label}
                description={item.detail}
                left={(props) => <List.Icon {...props} icon={item.icon} />}
              />
            ))
          )}
          <Button mode="text" disabled={!canRespond} onPress={() => undefined}>
            Update checklist
          </Button>
        </Surface>

        <Surface elevation={1} style={styles.surface}>
          <Text variant="titleMedium">Quick actions</Text>
          <View style={styles.actions}>
            <Button icon="plus" mode="contained" onPress={() => undefined}>
              Create event
            </Button>
            <Button icon="link-variant" mode="outlined" onPress={() => undefined}>
              Share invite
            </Button>
          </View>
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
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  divider: {
    marginTop: 4,
  },
  arrivalRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  arrivalMeta: {
    flex: 1,
  },
  sectionCaption: {
    opacity: 0.7,
  },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
});
