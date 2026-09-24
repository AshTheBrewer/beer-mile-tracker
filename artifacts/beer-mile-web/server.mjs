import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const port = Number(process.env.PORT || 3000);
const upstreamValue = process.env.API_UPSTREAM_URL;

if (!Number.isInteger(port) || port <= 0 || port > 65535) {
  throw new Error(`PORT must be a valid TCP port; received "${process.env.PORT}".`);
}

if (!upstreamValue) {
  throw new Error(
    'API_UPSTREAM_URL is required (for example, http://api.railway.internal:3000).',
  );
}

const upstream = new URL(upstreamValue);
if (!['http:', 'https:'].includes(upstream.protocol)) {
  throw new Error('API_UPSTREAM_URL must use http:// or https://.');
}
if (
  upstream.username ||
  upstream.password ||
  upstream.search ||
  upstream.hash ||
  (upstream.pathname !== '/' && upstream.pathname !== '')
) {
  throw new Error('API_UPSTREAM_URL must be an origin without credentials or a path.');
}

const publicDir = fileURLToPath(new URL('./dist/public/', import.meta.url));
const indexFile = resolve(publicDir, 'index.html');
const requestUpstream =
  upstream.protocol === 'https:' ? httpsRequest : httpRequest;

const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

const hopByHopHeaders = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

function firstHeaderValue(value) {
  return (Array.isArray(value) ? value[0] : value)?.split(',')[0]?.trim();
}

function proxyApi(req, res) {
  const target = new URL(req.url, upstream);
  const headers = { ...req.headers };
  for (const header of hopByHopHeaders) delete headers[header];

  const publicHost =
    firstHeaderValue(req.headers['x-forwarded-host']) ||
    firstHeaderValue(req.headers.host);
  const publicProtocol =
    firstHeaderValue(req.headers['x-forwarded-proto']) || 'https';
  const clientIp = req.socket.remoteAddress;

  if (publicHost) headers['x-forwarded-host'] = publicHost;
  headers['x-forwarded-proto'] = publicProtocol;
  if (clientIp) {
    const existing = firstHeaderValue(req.headers['x-forwarded-for']);
    headers['x-forwarded-for'] = existing ? `${existing}, ${clientIp}` : clientIp;
  }
  headers.host = upstream.host;

  const proxyReq = requestUpstream(
    target,
    { method: req.method, headers },
    (proxyRes) => {
      const responseHeaders = { ...proxyRes.headers };
      for (const header of hopByHopHeaders) delete responseHeaders[header];
      res.writeHead(proxyRes.statusCode || 502, responseHeaders);
      proxyRes.pipe(res);
    },
  );

  proxyReq.on('error', (error) => {
    console.error('API proxy request failed:', error.message);
    if (!res.headersSent) {
      const body = JSON.stringify({ error: 'API service unavailable' });
      res.writeHead(502, {
        'content-type': 'application/json; charset=utf-8',
        'content-length': Buffer.byteLength(body),
      });
      res.end(body);
    } else {
      res.destroy(error);
    }
  });
  req.on('aborted', () => proxyReq.destroy());
  req.pipe(proxyReq);
}

function sendFile(req, res, filePath) {
  let fileStat;
  try {
    fileStat = statSync(filePath);
  } catch {
    return false;
  }
  if (!fileStat.isFile()) return false;

  res.writeHead(200, {
    'content-type': mimeTypes[extname(filePath).toLowerCase()] || 'application/octet-stream',
    'content-length': fileStat.size,
    'cache-control':
      filePath === indexFile
        ? 'no-store'
        : 'public, max-age=31536000, immutable',
    'x-content-type-options': 'nosniff',
  });
  if (req.method === 'HEAD') res.end();
  else createReadStream(filePath).pipe(res);
  return true;
}

const server = createServer((req, res) => {
  const requestUrl = new URL(req.url || '/', 'http://localhost');

  if (requestUrl.pathname === '/api' || requestUrl.pathname.startsWith('/api/')) {
    proxyApi(req, res);
    return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { allow: 'GET, HEAD', 'content-length': '0' });
    res.end();
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(requestUrl.pathname);
  } catch {
    res.writeHead(400, { 'content-length': '0' });
    res.end();
    return;
  }

  const requestedFile = resolve(publicDir, `.${pathname}`);
  const isInsidePublicDir =
    requestedFile === publicDir || requestedFile.startsWith(`${publicDir}${sep}`);

  if (isInsidePublicDir && sendFile(req, res, requestedFile)) return;

  // Never serve the SPA document for a missing asset. Returning HTML with a
  // 200 status for a stale hashed JS/CSS URL causes browsers to report a
  // misleading strict-MIME-type module error.
  if (pathname.startsWith('/assets/') || extname(pathname)) {
    const body = 'Asset not found.\n';
    res.writeHead(404, {
      'cache-control': 'no-store',
      'content-length': Buffer.byteLength(body),
      'content-type': 'text/plain; charset=utf-8',
      'x-content-type-options': 'nosniff',
    });
    res.end(body);
    return;
  }

  if (sendFile(req, res, indexFile)) return;

  const body = 'Frontend build not found.\n';
  res.writeHead(503, {
    'content-type': 'text/plain; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
});

server.listen(port, '0.0.0.0', () => {
  console.log(`Beer Mile web server listening on port ${port}`);
});
