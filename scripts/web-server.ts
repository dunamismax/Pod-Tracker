import path from 'node:path';

const buildDir = path.resolve(process.cwd(), 'build/client');
const indexFile = Bun.file(path.join(buildDir, 'index.html'));
const fallbackHeaders = {
  'Content-Type': 'text/html; charset=utf-8',
};

function getAppPort(): number {
  const appUrl = process.env.APP_URL;

  if (appUrl) {
    const parsed = new URL(appUrl);
    const port = Number(parsed.port || (parsed.protocol === 'https:' ? 443 : 80));
    if (Number.isInteger(port) && port > 0) {
      return port;
    }
  }

  return 3000;
}

function resolveStaticPath(pathname: string): string | null {
  const relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const normalized = path.normalize(relativePath);

  if (normalized.startsWith('..') || path.isAbsolute(normalized)) {
    return null;
  }

  return path.join(buildDir, normalized);
}

const server = Bun.serve({
  port: getAppPort(),
  async fetch(request) {
    const url = new URL(request.url);
    const filePath = resolveStaticPath(decodeURIComponent(url.pathname));

    if (filePath) {
      const file = Bun.file(filePath);
      if (await file.exists()) {
        return new Response(file);
      }
    }

    return new Response(indexFile, {
      headers: fallbackHeaders,
    });
  },
});

console.log(`Web UI listening on http://localhost:${server.port}`);
