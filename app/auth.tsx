import { useEffect, useMemo, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import { Appbar, Button, HelperText, Surface, Text, TextInput, useTheme } from 'react-native-paper';

import { useProfile, useUpsertProfile } from '@/features/profiles/profiles-queries';
import { useSupabaseSession } from '@/hooks/use-supabase-session';
import {
  completeAuthFromParsed,
  parseAuthParamsFromUrl,
  redactSensitiveAuthUrl,
} from '@/lib/auth-link';
import { clearPendingMagicLinkEmail, setPendingMagicLinkEmail } from '@/lib/magic-link-state';
import { supabase } from '@/lib/supabase';

export default function AuthScreen() {
  const router = useRouter();
  const theme = useTheme();
  const { user, isLoading } = useSupabaseSession();
  const profileQuery = useProfile(user?.id);
  const upsertProfile = useUpsertProfile();
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [profileStatus, setProfileStatus] = useState<string | null>(null);
  const [lastMagicLinkSentAt, setLastMagicLinkSentAt] = useState<number | null>(null);
  const [cooldownSeconds, setCooldownSeconds] = useState(0);
  const [pastedMagicLinkUrl, setPastedMagicLinkUrl] = useState('');
  const [pastedMagicLinkStatus, setPastedMagicLinkStatus] = useState<string | null>(null);
  const [isFinalizingPastedMagicLink, setIsFinalizingPastedMagicLink] = useState(false);

  const [displayName, setDisplayName] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [contactHandle, setContactHandle] = useState('');
  const [contactNotes, setContactNotes] = useState('');

  const redirectTo = useMemo(() => Linking.createURL('auth/callback'), []);
  const emailError = email.length > 0 && !email.includes('@');

  useEffect(() => {
    if (!profileQuery.data) return;
    setDisplayName(profileQuery.data.display_name ?? '');
    setFirstName(profileQuery.data.first_name ?? '');
    setLastName(profileQuery.data.last_name ?? '');
    setPhone(profileQuery.data.phone ?? '');
    setContactEmail(profileQuery.data.contact_email ?? '');
    setContactHandle(profileQuery.data.contact_handle ?? '');
    setContactNotes(profileQuery.data.contact_notes ?? '');
  }, [profileQuery.data]);

  useEffect(() => {
    if (!lastMagicLinkSentAt) return;
    const tick = () => {
      const remainingMs = 60_000 - (Date.now() - lastMagicLinkSentAt);
      const remaining = Math.max(0, Math.ceil(remainingMs / 1000));
      setCooldownSeconds(remaining);
      if (remaining === 0) {
        setLastMagicLinkSentAt(null);
      }
    };
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [lastMagicLinkSentAt]);

  const handleMagicLink = async () => {
    if (!email || emailError || lastMagicLinkSentAt) return;
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail) return;

    setIsSubmitting(true);
    setStatus(null);
    setPastedMagicLinkStatus(null);
    setPendingMagicLinkEmail(normalizedEmail);

    const { error } = await supabase.auth.signInWithOtp({
      email: normalizedEmail,
      options: { emailRedirectTo: redirectTo },
    });

    if (error) {
      clearPendingMagicLinkEmail();
      if (error.status === 429) {
        setStatus('Too many requests. Please wait a minute and try again.');
      } else {
        setStatus(error.message);
      }
    } else {
      setStatus(
        'Magic link sent. Check your email to finish signing in. If it stays in Safari, paste the full URL below.'
      );
      setLastMagicLinkSentAt(Date.now());
    }

    setIsSubmitting(false);
  };

  const handleFinalizePastedMagicLink = async () => {
    if (!pastedMagicLinkUrl.trim()) return;

    const normalizedUrl = pastedMagicLinkUrl.trim().replace(/^['"]|['"]$/g, '');
    setStatus(null);
    setPastedMagicLinkStatus(null);
    setIsFinalizingPastedMagicLink(true);

    try {
      const parsed = parseAuthParamsFromUrl(normalizedUrl);
      const result = await completeAuthFromParsed(parsed);

      if (!result.handled) {
        const redactedUrl = redactSensitiveAuthUrl(normalizedUrl);
        setPastedMagicLinkStatus(
          `No auth data found in pasted URL. Pasted URL: ${redactedUrl ?? 'none'}`
        );
        return;
      }

      if (!result.sessionCreated) {
        setPastedMagicLinkStatus(result.message ?? 'Unable to finish sign-in from pasted URL.');
        return;
      }

      setPastedMagicLinkUrl('');
      setPastedMagicLinkStatus('Sign-in complete. Redirecting...');
      router.replace('/');
    } catch (error) {
      setPastedMagicLinkStatus(
        error instanceof Error ? error.message : 'Unable to finish sign-in from pasted URL.'
      );
    } finally {
      setIsFinalizingPastedMagicLink(false);
    }
  };

  const handleSignOut = async () => {
    setIsSubmitting(true);
    setStatus(null);
    const { error } = await supabase.auth.signOut();
    if (error) {
      setStatus(error.message);
    } else {
      clearPendingMagicLinkEmail();
    }
    setIsSubmitting(false);
  };

  const firstNameError = firstName.trim().length === 0;
  const lastNameError = lastName.trim().length === 0;
  const contactEmailError = contactEmail.length > 0 && !contactEmail.includes('@');

  const handleSaveProfile = async () => {
    if (!user || firstNameError || lastNameError || contactEmailError) return;
    setProfileStatus(null);
    try {
      await upsertProfile.mutateAsync({
        id: user.id,
        email: user.email ?? null,
        display_name: displayName.trim() ? displayName.trim() : null,
        first_name: firstName.trim(),
        last_name: lastName.trim(),
        phone: phone.trim() ? phone.trim() : null,
        contact_email: contactEmail.trim() ? contactEmail.trim() : null,
        contact_handle: contactHandle.trim() ? contactHandle.trim() : null,
        contact_notes: contactNotes.trim() ? contactNotes.trim() : null,
      });
      setProfileStatus('Profile saved.');
    } catch (error) {
      setProfileStatus(error instanceof Error ? error.message : 'Unable to save profile.');
    }
  };

  return (
    <View style={styles.screen}>
      <Appbar.Header elevated>
        <Appbar.BackAction onPress={() => router.back()} />
        <Appbar.Content title="Sign in" subtitle="Magic link only" />
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
              disabled={
                isSubmitting ||
                isFinalizingPastedMagicLink ||
                isLoading ||
                !email ||
                emailError ||
                Boolean(lastMagicLinkSentAt)
              }>
              {cooldownSeconds > 0 ? `Try again in ${cooldownSeconds}s` : 'Send magic link'}
            </Button>

            <TextInput
              mode="outlined"
              label="Paste magic link URL (fallback)"
              value={pastedMagicLinkUrl}
              onChangeText={setPastedMagicLinkUrl}
              autoCapitalize="none"
              autoCorrect={false}
              style={styles.input}
            />
            <Text variant="bodySmall" style={styles.caption}>
              If Safari opens a long URL instead of returning to the app, copy that full URL and
              paste it here.
            </Text>
            <Button
              mode="outlined"
              onPress={handleFinalizePastedMagicLink}
              disabled={
                isSubmitting ||
                isFinalizingPastedMagicLink ||
                isLoading ||
                !pastedMagicLinkUrl.trim()
              }>
              {isFinalizingPastedMagicLink ? 'Finishing sign-in...' : 'Sign in from pasted URL'}
            </Button>
            {pastedMagicLinkStatus ? (
              <Text variant="bodySmall" style={{ color: theme.colors.primary }}>
                {pastedMagicLinkStatus}
              </Text>
            ) : null}
          </Surface>

          <Surface elevation={1} style={styles.surface}>
            <Text variant="titleMedium">Session</Text>
            {isLoading ? (
              <Text variant="bodyMedium">Checking session...</Text>
            ) : user ? (
              <>
                <Text variant="bodyMedium">Signed in as {user.email ?? 'Unknown email'}.</Text>
                <Button
                  mode="contained"
                  onPress={handleSignOut}
                  disabled={isSubmitting || isFinalizingPastedMagicLink}>
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

          {user ? (
            <Surface elevation={1} style={styles.surface}>
              <Text variant="titleMedium">Your profile</Text>
              {profileQuery.isLoading ? (
                <Text variant="bodyMedium">Loading profile...</Text>
              ) : (
                <>
                  <TextInput
                    mode="outlined"
                    label="Display name (optional)"
                    value={displayName}
                    onChangeText={setDisplayName}
                    style={styles.input}
                  />
                  <TextInput
                    mode="outlined"
                    label="First name"
                    value={firstName}
                    onChangeText={setFirstName}
                    autoCapitalize="words"
                    style={styles.input}
                  />
                  <HelperText type="error" visible={firstNameError}>
                    First name is required.
                  </HelperText>
                  <TextInput
                    mode="outlined"
                    label="Last name"
                    value={lastName}
                    onChangeText={setLastName}
                    autoCapitalize="words"
                    style={styles.input}
                  />
                  <HelperText type="error" visible={lastNameError}>
                    Last name is required.
                  </HelperText>
                  <TextInput
                    mode="outlined"
                    label="Phone (optional)"
                    value={phone}
                    onChangeText={setPhone}
                    keyboardType="phone-pad"
                    style={styles.input}
                  />
                  <TextInput
                    mode="outlined"
                    label="Contact email (optional)"
                    value={contactEmail}
                    onChangeText={setContactEmail}
                    autoCapitalize="none"
                    keyboardType="email-address"
                    style={styles.input}
                  />
                  <HelperText type="error" visible={contactEmailError}>
                    Enter a valid contact email address.
                  </HelperText>
                  <TextInput
                    mode="outlined"
                    label="Contact handle (optional)"
                    value={contactHandle}
                    onChangeText={setContactHandle}
                    style={styles.input}
                  />
                  <TextInput
                    mode="outlined"
                    label="Notes (optional)"
                    value={contactNotes}
                    onChangeText={setContactNotes}
                    multiline
                    style={styles.input}
                  />
                  <Button
                    mode="contained"
                    onPress={handleSaveProfile}
                    disabled={
                      isLoading ||
                      profileQuery.isLoading ||
                      upsertProfile.isPending ||
                      firstNameError ||
                      lastNameError ||
                      contactEmailError
                    }>
                    Save profile
                  </Button>
                  {profileStatus ? (
                    <Text variant="bodySmall" style={{ color: theme.colors.primary }}>
                      {profileStatus}
                    </Text>
                  ) : null}
                </>
              )}
            </Surface>
          ) : null}
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
});
