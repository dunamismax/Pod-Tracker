import { env } from '../backend/env';

async function doctor() {
  console.log('scry doctor');
  console.log(`NODE_ENV=${env.NODE_ENV}`);
  console.log(`APP_URL=${env.APP_URL}`);
  console.log(`API_URL=${env.API_URL}`);
  console.log(`AUTH_URL=${env.AUTH_URL}`);
  console.log('Status: ok');
}

const command = Bun.argv[2];

if (command === 'doctor') {
  await doctor();
} else {
  console.error(`Unknown command: ${command ?? '<none>'}`);
  process.exitCode = 1;
}
