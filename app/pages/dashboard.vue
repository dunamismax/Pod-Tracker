<script setup lang="ts">
import { computed, reactive, ref } from 'vue';
import { definePageMeta, navigateTo, useAsyncData, useSeoMeta } from '#imports';
import { useAuth } from '~/composables/useAuth';
import { getApiErrorMessage } from '~/utils/api-error';
import { apiFetch } from '~/utils/api-fetch';

definePageMeta({
  middleware: ['auth'],
});

useSeoMeta({
  title: 'Dashboard | PodDashboard',
});

type Pod = {
  description: string | null;
  id: number;
  name: string;
  role: 'member' | 'owner';
};

type EventRecord = {
  id: number;
  location: string | null;
  podName: string | null;
  scheduledFor: string | null;
  title: string;
};

const auth = useAuth();
await auth.ensureLoaded();

const form = reactive({
  description: '',
  name: '',
});
const actionError = ref<string | null>(null);
// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
const currentUser = computed(() => auth.session.value);
// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
const canCreatePod = computed(() => form.name.trim().length >= 2);
const saving = ref(false);

// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
const { data, error, pending, refresh } = await useAsyncData('dashboard-data', async () => {
  const [podsResponse, eventsResponse] = await Promise.all([
    apiFetch<{ pods: Pod[] }>('/api/pods'),
    apiFetch<{ events: EventRecord[] }>('/api/events'),
  ]);

  return {
    events: eventsResponse.events,
    pods: podsResponse.pods,
  };
});

// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
async function createPod() {
  actionError.value = null;
  saving.value = true;

  try {
    await apiFetch('/api/pods', {
      method: 'POST',
      body: {
        description: form.description,
        name: form.name,
      },
    });

    form.name = '';
    form.description = '';
    await refresh();
  } catch (caught) {
    actionError.value = getApiErrorMessage(caught, 'Failed to create pod.');
  } finally {
    saving.value = false;
  }
}

// biome-ignore lint/correctness/noUnusedVariables: referenced by the template.
async function handleSignOut() {
  await auth.signOut();
  await navigateTo('/login');
}
</script>

<template>
  <main class="space-y-6 py-4">
    <header
      class="overflow-hidden rounded-[2rem] border border-white/10 bg-[color:var(--pod-panel-strong)] p-6 shadow-2xl shadow-cyan-950/20 ring-1 ring-white/5 backdrop-blur sm:p-8"
    >
      <div
        class="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-cyan-300/70 to-transparent"
      />
      <div class="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div class="space-y-4">
          <UBadge color="info" variant="soft" class="rounded-full px-3 py-1">
            Control Center
          </UBadge>
          <div class="space-y-2">
            <h1 class="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
              PodDashboard
            </h1>
            <p class="max-w-2xl text-sm leading-6 text-slate-300 sm:text-base">
              Pods, events, and the mildly suspicious confidence that comes from having the schedule
              in one place.
            </p>
          </div>
        </div>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <div class="rounded-2xl border border-white/10 bg-slate-950/30 px-4 py-3">
            <p class="text-xs uppercase tracking-[0.2em] text-slate-400">Signed in as</p>
            <p class="mt-1 text-sm font-medium text-slate-100">
              {{ currentUser?.email }}
            </p>
          </div>
          <UButton class="justify-center" color="neutral" variant="soft" size="lg" @click="handleSignOut">
            Sign out
          </UButton>
        </div>
      </div>
    </header>

    <p
      v-if="actionError || error"
      class="rounded-2xl border border-rose-400/35 bg-rose-950/40 px-4 py-3 text-sm text-rose-200"
    >
      {{ actionError ?? error?.message }}
    </p>

    <section class="grid gap-6 xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.35fr)]">
      <UCard
        class="border border-white/10 bg-[color:var(--pod-panel)] ring-1 ring-white/5 backdrop-blur"
        :ui="{ body: 'space-y-6 p-6 sm:p-7' }"
      >
        <div class="space-y-3">
          <p class="text-xs font-semibold uppercase tracking-[0.25em] text-amber-200/80">Workspace</p>
          <div>
            <h2 class="text-2xl font-semibold text-white">Create a pod</h2>
            <p class="mt-2 text-sm leading-6 text-slate-300">
              Start a new pod, become the owner, and stop organizing group logistics from memory.
            </p>
          </div>
        </div>

        <form class="space-y-4" @submit.prevent="createPod">
          <div class="space-y-2">
            <label class="text-sm text-slate-200" for="name">Pod name</label>
            <UInput
              id="name"
              v-model="form.name"
              size="xl"
              color="neutral"
              variant="outline"
              placeholder="Friday Pod"
            />
          </div>

          <div class="space-y-2">
            <label class="text-sm text-slate-200" for="description">Description</label>
            <UTextarea
              id="description"
              v-model="form.description"
              :rows="4"
              color="neutral"
              variant="outline"
              placeholder="Casual commander table, bring sleeves and snacks."
            />
          </div>

          <UButton
            class="w-full justify-center"
            size="xl"
            color="warning"
            :disabled="!canCreatePod"
            :loading="saving"
            type="submit"
          >
            Create pod
          </UButton>
        </form>
      </UCard>

      <div class="grid gap-6">
        <UCard
          class="border border-white/10 bg-[color:var(--pod-panel)] ring-1 ring-white/5 backdrop-blur"
          :ui="{ body: 'space-y-5 p-6 sm:p-7' }"
        >
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-200/80">Membership</p>
              <h2 class="mt-2 text-2xl font-semibold text-white">Your pods</h2>
            </div>
            <UBadge color="neutral" variant="outline" class="rounded-full px-3 py-1">
              {{ data?.pods.length ?? 0 }} total
            </UBadge>
          </div>

          <div v-if="pending" class="text-sm text-slate-300">Loading pods...</div>
          <div v-else-if="!data?.pods.length" class="rounded-2xl border border-dashed border-white/10 px-4 py-5 text-sm text-slate-300">
            No pods yet. Create the first one and the dashboard stops feeling like an abandoned bridge.
          </div>
          <ul v-else class="grid gap-3">
            <li
              v-for="pod in data.pods"
              :key="pod.id"
              class="rounded-3xl border border-white/10 bg-slate-950/30 p-4"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="text-base font-semibold text-white">{{ pod.name }}</p>
                  <p v-if="pod.description" class="mt-1 text-sm leading-6 text-slate-300">
                    {{ pod.description }}
                  </p>
                </div>
                <UBadge :color="pod.role === 'owner' ? 'warning' : 'neutral'" variant="soft" class="rounded-full">
                  {{ pod.role }}
                </UBadge>
              </div>
            </li>
          </ul>
        </UCard>

        <UCard
          class="border border-white/10 bg-[color:var(--pod-panel)] ring-1 ring-white/5 backdrop-blur"
          :ui="{ body: 'space-y-5 p-6 sm:p-7' }"
        >
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-200/80">Schedule</p>
            <h2 class="mt-2 text-2xl font-semibold text-white">Upcoming events</h2>
          </div>

          <div v-if="pending" class="text-sm text-slate-300">Loading events...</div>
          <div v-else-if="!data?.events.length" class="rounded-2xl border border-dashed border-white/10 px-4 py-5 text-sm text-slate-300">
            No upcoming events. Quiet is fine, but now you know it is quiet on purpose.
          </div>
          <ul v-else class="grid gap-3 lg:grid-cols-2">
            <li
              v-for="event in data.events"
              :key="event.id"
              class="rounded-3xl border border-white/10 bg-slate-950/30 p-4"
            >
              <div class="space-y-2">
                <p class="text-base font-semibold text-white">{{ event.title }}</p>
                <p class="text-sm leading-6 text-slate-300">
                  {{ event.podName ?? 'Unknown pod' }}
                </p>
                <p class="text-sm text-slate-400">
                  {{ event.scheduledFor ? new Date(event.scheduledFor).toLocaleString() : 'TBD' }}
                </p>
                <p v-if="event.location" class="text-xs uppercase tracking-[0.2em] text-amber-200/75">
                  {{ event.location }}
                </p>
              </div>
            </li>
          </ul>
        </UCard>
      </div>
    </section>
  </main>
</template>
