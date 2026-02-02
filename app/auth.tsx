import { useMemo, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import { Appbar, Button, HelperText, Surface, Text, TextInput, useTheme } from 'react-native-paper';

import { useSupabaseSession } from '@/hooks/use-supabase-session';
import { supabase } from '@/lib/supabase';

WebBrowser.maybeCompleteAuthSession();

const oauthProviders = [
  { id: 'github', label: 'GitHub' },
  { id: 'google', label: 'Google' },
] as const;

export default function AuthScreen() {
  const router = useRouter();
  const theme = useTheme();
  const { user, isLoading } = useSupabaseSession();
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const redirectTo = useMemo(() => Linking.createURL('auth/callback'), []);
  const emailError = email.length > 0 && !email.includes('@');

  const handleMagicLink = async () => {
    if (!email || emailError) return;
    setIsSubmitting(true);
    setStatus(null);

    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: redirectTo },
    });

    if (error) {
      setStatus(error.message);
    } else {
      setStatus('Magic link sent. Check your email to finish signing in.');
    }

    setIsSubmitting(false);
  };

  const handleOAuth = async (provider: (typeof oauthProviders)[number]['id']) => {
    setIsSubmitting(true);
    setStatus(null);

    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo,
        skipBrowserRedirect: true,
      },
    });

    if (error) {
      setStatus(error.message);
      setIsSubmitting(false);
      return;
    }

    if (data?.url) {
      const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
      if (result.type === 'success' && result.url) {
        await supabase.auth.getSession();
      }
    }

    setIsSubmitting(false);
  };

  const handleSignOut = async () => {
    setIsSubmitting(true);
    setStatus(null);
    const { error } = await supabase.auth.signOut();
    if (error) {
      setStatus(error.message);
    }
    setIsSubmitting(false);
  };

  return (
    <View style={styles.screen}>
      <Appbar.Header elevated>
        <Appbar.BackAction onPress={() => router.back()} />
        <Appbar.Content title="Sign in" subtitle="Magic link or OAuth" />
      </Appbar.Header>
      <KeyboardAvoidingView
        style={styles.keyboard}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.content}>
          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">Magic link</Text>
            <Text variant="bodySmall" style={styles.caption}>
              We will email you a secure sign-in link.
            </Text>
            <TextInput
              mode="outlined"
              label="Email"
              value={email}
              onChangeText={setEmail}
              autoCapitalize="none"
              keyboardType="email-address"
              autoComplete="email"
              style={styles.input}
            />
            <HelperText type="error" visible={emailError}>
              Enter a valid email address.
            </HelperText>
            <Button
              mode="contained"
              onPress={handleMagicLink}
              disabled={isSubmitting || isLoading || !email || emailError}>
              Send magic link
            </Button>
          </Surface>

          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">OAuth</Text>
            <Text variant="bodySmall" style={styles.caption}>
              Use a connected account to sign in instantly.
            </Text>
            <View style={styles.oauthButtons}>
              {oauthProviders.map((provider) => (
                <Button
                  key={provider.id}
                  mode="outlined"
                  onPress={() => handleOAuth(provider.id)}
                  disabled={isSubmitting || isLoading}>
                  Continue with {provider.label}
                </Button>
              ))}
            </View>
          </Surface>

          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">Session</Text>
            {isLoading ? (
              <Text variant="bodyMedium">Checking session...</Text>
            ) : user ? (
              <>
                <Text variant="bodyMedium">Signed in as {user.email ?? 'Unknown email'}.</Text>
                <Button mode="contained" onPress={handleSignOut} disabled={isSubmitting}>
                  Sign out
                </Button>
              </>
            ) : (
              <Text variant="bodyMedium">You are not signed in yet.</Text>
            )}
            {status ? (
              <Text variant="bodySmall" style={{ color: theme.colors.primary }}>
                {status}
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
  caption: {
    opacity: 0.7,
  },
  input: {
    backgroundColor: 'transparent',
  },
  oauthButtons: {
    gap: 12,
  },
});
