<script setup lang="ts">
import { reactive, ref } from 'vue';
import { definePageMeta, navigateTo, useSeoMeta } from '#imports';
import { useAuth } from '~/composables/useAuth';
import { getApiErrorMessage } from '~/utils/api-error';
import { apiFetch } from '~/utils/api-fetch';

definePageMeta({
  middleware: ['guest'],
});

useSeoMeta({
  title: 'Register | PodDashboard',
});

const auth = useAuth();
const form = reactive({
  email: '',
  name: '',
  password: '',
  passwordConfirmation: '',
});
const error = ref<string | null>(null);
const pending = ref(false);

// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
async function handleSubmit() {
  error.value = null;
  pending.value = true;

  try {
    await apiFetch('/api/register', {
      method: 'POST',
      body: form,
    });

    await auth.signIn({
      email: form.email,
      password: form.password,
    });

    await navigateTo('/dashboard');
  } catch (caught) {
    error.value = getApiErrorMessage(caught, 'Registration failed.');
  } finally {
    pending.value = false;
  }
}
</script>

<template>
  <main class="flex min-h-[calc(100vh-3rem)] items-center justify-center">
    <UCard
      class="w-full max-w-xl border border-white/10 bg-[color:var(--pod-panel)] shadow-2xl shadow-amber-950/30 ring-1 ring-white/5 backdrop-blur"
      :ui="{ body: 'space-y-6 p-8 sm:p-9' }"
    >
      <div class="space-y-3">
        <p class="text-xs font-semibold uppercase tracking-[0.28em] text-amber-200/85">New Crew</p>
        <div class="space-y-2">
          <h1 class="text-3xl font-semibold text-white">Create account</h1>
          <p class="text-sm text-slate-300">
            Join the dashboard, claim your seat, and keep the pod list from becoming folklore.
          </p>
        </div>
      </div>

      <form class="grid gap-4 sm:grid-cols-2" @submit.prevent="handleSubmit">
        <div class="space-y-2 sm:col-span-2">
          <label class="text-sm text-slate-200" for="name">Name</label>
          <UInput
            id="name"
            v-model="form.name"
            size="xl"
            color="neutral"
            variant="outline"
            placeholder="Test User"
          />
        </div>

        <div class="space-y-2 sm:col-span-2">
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
          />
        </div>

        <div class="space-y-2">
          <label class="text-sm text-slate-200" for="passwordConfirmation">Confirm password</label>
          <UInput
            id="passwordConfirmation"
            v-model="form.passwordConfirmation"
            type="password"
            size="xl"
            color="neutral"
            variant="outline"
          />
        </div>

        <p
          v-if="error"
          class="rounded-2xl border border-rose-400/35 bg-rose-950/40 px-3 py-2 text-sm text-rose-200 sm:col-span-2"
        >
          {{ error }}
        </p>

        <div class="sm:col-span-2">
          <UButton class="w-full justify-center" size="xl" color="warning" :loading="pending" type="submit">
            Create account
          </UButton>
        </div>
      </form>

      <p class="text-sm text-slate-300">
        Already have an account?
        <NuxtLink class="font-medium text-cyan-300 transition hover:text-cyan-200" to="/login">
          Sign in
        </NuxtLink>
      </p>
    </UCard>
  </main>
</template>
