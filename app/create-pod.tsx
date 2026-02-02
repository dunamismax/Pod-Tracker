import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import {
  Appbar,
  Button,
  HelperText,
  Surface,
  Text,
  TextInput,
  useTheme,
} from 'react-native-paper';

import { useCreatePod } from '@/features/pods/pods-queries';
import { useSupabaseSession } from '@/hooks/use-supabase-session';

export default function CreatePodScreen() {
  const router = useRouter();
  const theme = useTheme();
  const { user, isLoading } = useSupabaseSession();
  const createPod = useCreatePod();

  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [location, setLocation] = useState('');
  const [status, setStatus] = useState<string | null>(null);

  const nameError = name.trim().length === 0;

  const handleSubmit = async () => {
    if (!user || nameError) return;
    setStatus(null);

    try {
      await createPod.mutateAsync({
        userId: user.id,
        name: name.trim(),
        description: description.trim() ? description.trim() : null,
        locationText: location.trim() ? location.trim() : null,
      });
      setStatus('Pod created.');
      router.replace('/');
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Unable to create pod.');
    }
  };

  return (
    <View style={styles.screen}>
      <Appbar.Header elevated>
        <Appbar.BackAction onPress={() => router.back()} />
        <Appbar.Content title="Create pod" subtitle="Your trusted circle" />
      </Appbar.Header>
      <KeyboardAvoidingView
        style={styles.keyboard}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.content}>
          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">Pod details</Text>
            <TextInput
              mode="outlined"
              label="Pod name"
              value={name}
              onChangeText={setName}
              autoCapitalize="words"
              style={styles.input}
            />
            <HelperText type="error" visible={nameError}>
              Pod name is required.
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
            <Button
              mode="contained"
              onPress={handleSubmit}
              disabled={isLoading || !user || nameError || createPod.isPending}>
              Create pod
            </Button>
            {status ? (
              <Text variant="bodySmall" style={{ color: theme.colors.primary }}>
                {status}
              </Text>
            ) : null}
            {!user && !isLoading ? (
              <Text variant="bodySmall" style={styles.caption}>
                Sign in to create a pod.
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
