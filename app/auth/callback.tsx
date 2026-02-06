import { useEffect, useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import { ActivityIndicator, Text } from 'react-native-paper';

import {
  completeAuthFromParsed,
  parseAuthParamsFromRouteParams,
  parseAuthParamsFromUrl,
  redactSensitiveAuthUrl,
  type RouteAuthParams,
} from '@/lib/auth-link';
import { supabase } from '@/lib/supabase';

export default function AuthCallbackScreen() {
  const router = useRouter();
  const url = Linking.useURL();
  const routeParams = useLocalSearchParams();
  const [message, setMessage] = useState('Finalizing your sign-in...');
  const processedUrlRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    let isMounted = true;
    const setScreenMessage = (value: string) => {
      if (isMounted) setMessage(value);
    };

    const finalizeFromParsed = async (rawParams: ReturnType<typeof parseAuthParamsFromUrl>) => {
      const result = await completeAuthFromParsed(rawParams);
      if (!result.handled) {
        return false;
      }
      if (!result.sessionCreated) {
        setScreenMessage(result.message ?? 'Unable to sign in.');
        return true;
      }
      router.replace('/');
      return true;
    };

    const finalizeFromUrl = async (rawUrl: string | null) => {
      if (!rawUrl || processedUrlRef.current.has(rawUrl)) return false;
      processedUrlRef.current.add(rawUrl);
      return finalizeFromParsed(parseAuthParamsFromUrl(rawUrl));
    };

    const finalize = async () => {
      try {
        const finalizedCurrent = await finalizeFromUrl(url);
        if (finalizedCurrent) return;

        const initialUrl = await Linking.getInitialURL();
        const finalizedInitial = await finalizeFromUrl(initialUrl);
        if (finalizedInitial) return;

        const finalizedRouteParams = await finalizeFromParsed(
          parseAuthParamsFromRouteParams(routeParams as RouteAuthParams)
        );
        if (finalizedRouteParams) return;

        const {
          data: { session },
        } = await supabase.auth.getSession();

        if (session) {
          router.replace('/');
          return;
        }

        const redactedCurrent = redactSensitiveAuthUrl(url);
        const redactedInitial = redactSensitiveAuthUrl(initialUrl);
        setScreenMessage(
          `No auth data found in the link. URL: ${redactedCurrent ?? 'none'} | Initial URL: ${redactedInitial ?? 'none'}`
        );
      } catch (error) {
        setScreenMessage(error instanceof Error ? error.message : 'Unable to finish sign-in.');
      }
    };

    void finalize();

    return () => {
      isMounted = false;
    };
  }, [routeParams, router, url]);

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
