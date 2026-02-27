import { defineNuxtConfig } from 'nuxt/config';

export default defineNuxtConfig({
  ssr: false,
  modules: ['@nuxt/ui'],
  css: ['~/assets/css/main.css'],
  runtimeConfig: {
    apiBaseUrl: process.env.API_URL ?? 'http://localhost:3001',
    public: {
      appName: 'PodDashboard',
    },
  },
  devtools: {
    enabled: false,
  },
});
