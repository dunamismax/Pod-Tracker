import { useEffect, useMemo, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import {
  Appbar,
  Button,
  HelperText,
  List,
  Surface,
  Text,
  TextInput,
  useTheme,
} from 'react-native-paper';
import DateTimePicker, { type DateTimePickerEvent } from '@react-native-community/datetimepicker';

import { useCreateEvent } from '@/features/events/events-queries';
import { usePodsByUser } from '@/features/pods/pods-queries';
import { useSupabaseSession } from '@/hooks/use-supabase-session';

function toInputDateTime(date: Date) {
  const pad = (value: number) => value.toString().padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours()
  )}:${pad(date.getMinutes())}`;
}

function toIsoString(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

function formatDateTimeLabel(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return 'Select a time';
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(parsed);
}

export default function CreateEventScreen() {
  const router = useRouter();
  const theme = useTheme();
  const { user, isLoading } = useSupabaseSession();
  const podsQuery = usePodsByUser(user?.id);
  const createEvent = useCreateEvent();

  const initialStart = useMemo(() => {
    const now = new Date();
    now.setMinutes(Math.ceil(now.getMinutes() / 15) * 15, 0, 0);
    return toInputDateTime(now);
  }, []);

  const [podId, setPodId] = useState<string>('');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [location, setLocation] = useState('');
  const [startsAt, setStartsAt] = useState(initialStart);
  const [endsAt, setEndsAt] = useState('');
  const [showStartPicker, setShowStartPicker] = useState(false);
  const [showEndPicker, setShowEndPicker] = useState(false);
  const [status, setStatus] = useState<string | null>(null);

  useEffect(() => {
    if (!podId && podsQuery.data && podsQuery.data.length > 0) {
      setPodId(podsQuery.data[0].id);
    }
  }, [podId, podsQuery.data]);

  const titleError = title.trim().length === 0;
  const startsAtIso = toIsoString(startsAt);
  const endsAtIso = endsAt ? toIsoString(endsAt) : null;
  const startsAtError = !startsAtIso;
  const endsAtError = Boolean(endsAt && !endsAtIso);
  const isWeb = Platform.OS === 'web';

  const handleStartChange = (_event: DateTimePickerEvent, selectedDate?: Date) => {
    setShowStartPicker(false);
    if (selectedDate) {
      setStartsAt(toInputDateTime(selectedDate));
    }
  };

  const handleEndChange = (_event: DateTimePickerEvent, selectedDate?: Date) => {
    setShowEndPicker(false);
    if (selectedDate) {
      setEndsAt(toInputDateTime(selectedDate));
    }
  };

  const handleSubmit = async () => {
    if (!user || !podId || titleError || startsAtError || endsAtError) return;
    setStatus(null);

    try {
      await createEvent.mutateAsync({
        userId: user.id,
        podId,
        title: title.trim(),
        description: description.trim() ? description.trim() : null,
        locationText: location.trim() ? location.trim() : null,
        startsAt: startsAtIso ?? new Date().toISOString(),
        endsAt: endsAtIso,
      });
      setStatus('Event created.');
      router.replace('/');
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Unable to create event.');
    }
  };

  return (
    <View style={styles.screen}>
      <Appbar.Header elevated>
        <Appbar.BackAction onPress={() => router.back()} />
        <Appbar.Content title="Create event" subtitle="Plan the next gather" />
      </Appbar.Header>
      <KeyboardAvoidingView
        style={styles.keyboard}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.content}>
          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">Choose a pod</Text>
            {podsQuery.isLoading ? (
              <Text variant="bodyMedium">Loading pods...</Text>
            ) : podsQuery.data && podsQuery.data.length > 0 ? (
              podsQuery.data.map((pod) => (
                <List.Item
                  key={pod.id}
                  title={pod.name}
                  description={pod.location_text ?? 'No location set'}
                  onPress={() => setPodId(pod.id)}
                  right={(props) =>
                    podId === pod.id ? <List.Icon {...props} icon="check-circle" /> : null
                  }
                />
              ))
            ) : (
              <>
                <Text variant="bodyMedium">Create a pod before scheduling events.</Text>
                <Button mode="outlined" onPress={() => router.push('/create-pod')}>
                  Create a pod
                </Button>
              </>
            )}
          </Surface>

          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">Event details</Text>
            <TextInput
              mode="outlined"
              label="Title"
              value={title}
              onChangeText={setTitle}
              style={styles.input}
            />
            <HelperText type="error" visible={titleError}>
              Event title is required.
            </HelperText>
            <TextInput
              mode="outlined"
              label="Description (optional)"
              value={description}
              onChangeText={setDescription}
              multiline
              style={styles.input}
            />
            <TextInput
              mode="outlined"
              label="Location (optional)"
              value={location}
              onChangeText={setLocation}
              style={styles.input}
            />
            {isWeb ? (
              <>
                <TextInput
                  mode="outlined"
                  label="Starts at (YYYY-MM-DDTHH:mm)"
                  value={startsAt}
                  onChangeText={setStartsAt}
                  style={styles.input}
                />
                <HelperText type="error" visible={startsAtError}>
                  Enter a valid start time (example: 2026-02-02T18:30).
                </HelperText>
                <TextInput
                  mode="outlined"
                  label="Ends at (optional)"
                  value={endsAt}
                  onChangeText={setEndsAt}
                  style={styles.input}
                />
                <HelperText type="error" visible={endsAtError}>
                  Enter a valid end time (example: 2026-02-02T20:30).
                </HelperText>
              </>
            ) : (
              <>
                <List.Item
                  title="Starts at"
                  description={formatDateTimeLabel(startsAt)}
                  right={() => (
                    <Button mode="outlined" onPress={() => setShowStartPicker(true)}>
                      Pick
                    </Button>
                  )}
                />
                <List.Item
                  title="Ends at"
                  description={endsAt ? formatDateTimeLabel(endsAt) : 'Optional'}
                  right={() => (
                    <Button mode="outlined" onPress={() => setShowEndPicker(true)}>
                      Pick
                    </Button>
                  )}
                />
                {startsAtError ? (
                  <HelperText type="error" visible={startsAtError}>
                    Select a valid start time.
                  </HelperText>
                ) : null}
                {endsAtError ? (
                  <HelperText type="error" visible={endsAtError}>
                    Select a valid end time.
                  </HelperText>
                ) : null}
                {showStartPicker ? (
                  <DateTimePicker
                    value={startsAtIso ? new Date(startsAtIso) : new Date()}
                    mode="datetime"
                    onChange={handleStartChange}
                  />
                ) : null}
                {showEndPicker ? (
                  <DateTimePicker
                    value={endsAtIso ? new Date(endsAtIso) : new Date()}
                    mode="datetime"
                    onChange={handleEndChange}
                  />
                ) : null}
              </>
            )}
            <Button
              mode="contained"
              onPress={handleSubmit}
              disabled={
                isLoading ||
                !user ||
                !podId ||
                titleError ||
                startsAtError ||
                endsAtError ||
                createEvent.isPending
              }>
              Create event
            </Button>
            {status ? (
              <Text variant="bodySmall" style={{ color: theme.colors.primary }}>
                {status}
              </Text>
            ) : null}
            {!user && !isLoading ? (
              <Text variant="bodySmall" style={styles.caption}>
                Sign in to create events.
              </Text>
            ) : null}
          </Surface>
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  keyboard: {
    flex: 1,
  },
  content: {
    padding: 20,
    gap: 20,
  },
  surface: {
    padding: 16,
    borderRadius: 16,
    gap: 12,
  },
  input: {
    backgroundColor: 'transparent',
  },
  caption: {
    opacity: 0.7,
  },
});
