<script setup lang="ts">
import { navigateTo } from '#imports';
import { useAuth } from '~/composables/useAuth';

const auth = useAuth();
const session = await auth.ensureLoaded();

await navigateTo(session.authenticated ? '/dashboard' : '/login', {
  replace: true,
});
</script>

<template>
  <div />
</template>
