import { defineEventHandler, proxyRequest } from 'h3';
import { joinURL } from 'ufo';
import { useRuntimeConfig } from '#imports';

export default defineEventHandler((event) => {
  const runtimeConfig = useRuntimeConfig(event);
  const path = event.context.params?.path ?? '';
  const target = joinURL(runtimeConfig.apiBaseUrl, 'api', path);

  return proxyRequest(event, target);
});
