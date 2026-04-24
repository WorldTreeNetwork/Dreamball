/**
 * Playwright configuration for S2.1 browser parity tests (D-015 R2 gate).
 *
 * Tests run in Playwright Chromium only (MVP per OQ3/R1 risk).
 * The webServer serves:
 *   /kuzu-wasm/*         — kuzu-wasm browser bundle + worker
 *   /fixture-data.js     — pre-generated 100-vector fixture (270 KB)
 *   /                    — index.html test harness
 *
 * Run: bun run test:e2e
 *
 * Note: kuzu-wasm@0.11.3 browser build requires same-origin worker scripts.
 * The static server below fulfils this requirement without COOP/COEP headers
 * because the default (non-multithreaded) kuzu-wasm build does not require
 * cross-origin isolation.
 */

import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.e2e.ts',
  timeout: 120_000, // kuzu-wasm WASM init + 100-vector insert can be slow
  retries: 0,
  workers: 1,

  use: {
    headless: true,
    // Browser console is forwarded to test output for debugging
    // Chromium only — per OQ3/R1 risk: kuzu-wasm@0.11.3 validated on Chromium only
  },

  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        // Allow SharedArrayBuffer-free operation (default kuzu-wasm build)
        launchOptions: {
          args: []
        }
      }
    }
  ],

  webServer: [
    {
      // S2.1 parity fixture server — port 4321
      // Simple static file server for the parity test page + kuzu-wasm assets.
      command: `node --input-type=module <<'EOJS'
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = '${__dirname}';
const PORT = 4321;

const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
};

const PATHS = {
  '/': path.join(ROOT, 'tests/parity-fixture/index.html'),
  '/fixture-data.js': path.join(ROOT, 'tests/parity-fixture/fixture-data.js'),
  '/kuzu-wasm/index.js': path.join(ROOT, 'node_modules/kuzu-wasm/index.js'),
  '/kuzu-wasm/kuzu_wasm_worker.js': path.join(ROOT, 'node_modules/kuzu-wasm/kuzu_wasm_worker.js'),
};

// Also serve any file under node_modules/kuzu-wasm/ (wasm binary etc)
const WASM_DIR = path.join(ROOT, 'node_modules/kuzu-wasm');

http.createServer((req, res) => {
  let filePath = PATHS[req.url] || null;
  if (!filePath && req.url?.startsWith('/kuzu-wasm/')) {
    const rel = req.url.slice('/kuzu-wasm/'.length);
    filePath = path.join(WASM_DIR, rel);
  }
  if (!filePath || !fs.existsSync(filePath)) {
    res.writeHead(404); res.end('Not found: ' + req.url); return;
  }
  const ext = path.extname(filePath);
  res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
  fs.createReadStream(filePath).pipe(res);
}).listen(PORT, () => console.log('parity-server listening on ' + PORT));
EOJS`,
      url: 'http://localhost:4321',
      reuseExistingServer: !process.env.CI,
      timeout: 15_000
    },
    {
      // S2.3 store-browser fixture server — port 4322
      // Serves tests/store-fixture/index.html + kuzu-wasm assets + static worker.
      // static/kuzu_wasm_worker.js is served at /kuzu_wasm_worker.js (AC2).
      command: `node --input-type=module <<'EOJS'
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = '${__dirname}';
const PORT = 4322;

const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
};

const STATIC_DIR = path.join(ROOT, 'static');
const WASM_DIR = path.join(ROOT, 'node_modules/kuzu-wasm');

http.createServer((req, res) => {
  let filePath = null;
  const url = req.url || '/';

  if (url === '/' || url === '/index.html') {
    filePath = path.join(ROOT, 'tests/store-fixture/index.html');
  } else if (url === '/kuzu_wasm_worker.js') {
    // AC2: worker served from static/ (bootstrap copies it there)
    filePath = path.join(STATIC_DIR, 'kuzu_wasm_worker.js');
    // Fallback: serve from node_modules if bootstrap hasn't run yet
    if (!fs.existsSync(filePath)) {
      filePath = path.join(WASM_DIR, 'kuzu_wasm_worker.js');
    }
  } else if (url.startsWith('/kuzu-wasm/')) {
    const rel = url.slice('/kuzu-wasm/'.length);
    filePath = path.join(WASM_DIR, rel);
  }

  if (!filePath || !fs.existsSync(filePath)) {
    res.writeHead(404); res.end('Not found: ' + url); return;
  }
  const ext = path.extname(filePath);
  res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
  fs.createReadStream(filePath).pipe(res);
}).listen(PORT, () => console.log('store-server listening on ' + PORT));
EOJS`,
      url: 'http://localhost:4322',
      reuseExistingServer: !process.env.CI,
      timeout: 15_000
    }
  ]
});
