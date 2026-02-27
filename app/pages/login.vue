<script setup lang="ts">
import { reactive, ref } from 'vue';
import { definePageMeta, navigateTo, useSeoMeta } from '#imports';
import { useAuth } from '~/composables/useAuth';
import { getApiErrorMessage } from '~/utils/api-error';

definePageMeta({
  middleware: ['guest'],
});

useSeoMeta({
  title: 'Sign In | PodDashboard',
});

const auth = useAuth();
const form = reactive({
  email: '',
  password: '',
});
const error = ref<string | null>(null);
const pending = ref(false);

// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
async function handleSubmit() {
  error.value = null;
  pending.value = true;

  try {
    await auth.signIn({
      email: form.email,
      password: form.password,
    });

    await navigateTo('/dashboard');
  } catch (caught) {
    error.value = getApiErrorMessage(caught, 'Invalid credentials.');
  } finally {
    pending.value = false;
  }
}
</script>

<template>
  <main class="flex min-h-[calc(100vh-3rem)] items-center justify-center">
    <UCard
      class="w-full max-w-md border border-white/10 bg-[color:var(--pod-panel)] shadow-2xl shadow-cyan-950/30 ring-1 ring-white/5 backdrop-blur"
      :ui="{ body: 'space-y-6 p-8 sm:p-9' }"
    >
      <div class="space-y-3">
        <p class="text-xs font-semibold uppercase tracking-[0.28em] text-cyan-200/80">Auth</p>
        <div class="space-y-2">
          <h1 class="text-3xl font-semibold text-white">Sign in</h1>
          <p class="text-sm text-slate-300">
            Get back to your pods, your events, and whatever chaos you scheduled on purpose.
          </p>
        </div>
      </div>

      <form class="space-y-4" @submit.prevent="handleSubmit">
        <div class="space-y-2">
          <label class="text-sm text-slate-200" for="email">Email</label>
          <UInput
            id="email"
            v-model="form.email"
            type="email"
            size="xl"
            color="neutral"
            variant="outline"
            placeholder="test@example.com"
          />
        </div>

        <div class="space-y-2">
          <label class="text-sm text-slate-200" for="password">Password</label>
          <UInput
            id="password"
            v-model="form.password"
            type="password"
            size="xl"
            color="neutral"
            variant="outline"
            placeholder="password"
          />
        </div>

        <p v-if="error" class="rounded-2xl border border-rose-400/35 bg-rose-950/40 px-3 py-2 text-sm text-rose-200">
          {{ error }}
        </p>

        <UButton class="w-full justify-center" size="xl" color="warning" :loading="pending" type="submit">
          Sign in
        </UButton>
      </form>

      <div class="rounded-2xl border border-white/10 bg-slate-950/30 px-4 py-3 text-sm text-slate-300">
        Seeded admin for local validation: <span class="font-medium text-white">test@example.com</span> /
        <span class="font-medium text-white">password</span>
      </div>

      <p class="text-sm text-slate-300">
        Need an account?
        <NuxtLink class="font-medium text-cyan-300 transition hover:text-cyan-200" to="/register">
          Register
        </NuxtLink>
      </p>
    </UCard>
  </main>
</template>
