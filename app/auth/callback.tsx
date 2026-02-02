import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import { ActivityIndicator, Text } from 'react-native-paper';

import { supabase } from '@/lib/supabase';

export default function AuthCallbackScreen() {
  const router = useRouter();
  const url = Linking.useURL();
  const [message, setMessage] = useState('Finalizing your sign-in...');

  useEffect(() => {
    if (!url) return;

    const finalize = async () => {
      const parsedUrl = new URL(url);
      const authCode = parsedUrl.searchParams.get('code');

      if (authCode) {
        const { error } = await supabase.auth.exchangeCodeForSession(url);
        if (error) {
          setMessage(error.message);
          return;
        }
      } else {
        setMessage('Session already detected. Redirecting...');
      }

      router.replace('/');
    };

    finalize();
  }, [router, url]);

  return (
    <View style={styles.screen}>
      <ActivityIndicator />
      <Text variant="bodyMedium" style={styles.message}>
        {message}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    padding: 24,
  },
  message: {
    textAlign: 'center',
  },
});
