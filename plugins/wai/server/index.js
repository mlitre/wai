const http = require('http');
const fs = require('fs');
const path = require('path');

const SESSION_DIR = process.env.DS_DIR;
const BIND_HOST = process.env.DS_HOST || '127.0.0.1';
const URL_HOST = process.env.DS_URL_HOST || 'localhost';
const OWNER_PID = parseInt(process.env.DS_OWNER_PID || '0', 10);
const PROJECT_DIR = process.env.DS_PROJECT_DIR ? path.resolve(process.env.DS_PROJECT_DIR) : null;

if (!SESSION_DIR) {
  console.error('DS_DIR environment variable is required');
  process.exit(1);
}

const STATE_DIR = path.join(SESSION_DIR, 'state');
const PLUGIN_ROOT = path.resolve(__dirname, '..');
const UI_DIR = path.join(PLUGIN_ROOT, 'ui');
const VENDOR_DIR = path.join(PLUGIN_ROOT, 'vendor');
const SERVER_VERSION = '2.0.0';

const IDLE_TIMEOUT_DEFAULT_MS = 20 * 60 * 1000;
const parsedIdle = Number(process.env.DS_IDLE_TIMEOUT_MS);
const IDLE_TIMEOUT_MS = Number.isFinite(parsedIdle) && parsedIdle > 0 ? parsedIdle : IDLE_TIMEOUT_DEFAULT_MS;
const OWNER_CHECK_INTERVAL_MS = 30 * 1000; // 30 seconds
const STALE_SESSION_MAX_AGE_MS = 24 * 60 * 60 * 1000; // 24 hours

let lastActivity = Date.now();

const { execFileSync } = require('child_process');

function getGitContext(cwd) {
  var ctx = { branch: null, isGitButler: false, baseline: 'HEAD', baselineLabel: 'Uncommitted changes' };

  try {
    var gbPath = path.join(cwd, '.git', 'gitbutler');
    if (fs.existsSync(gbPath)) {
      ctx.isGitButler = true;
      try {
        var vbPath = path.join(cwd, '.git', 'gitbutler', 'virtual_branches.toml');
        if (fs.existsSync(vbPath)) {
          var vbContent = fs.readFileSync(vbPath, 'utf8');
          var nameMatch = vbContent.match(/name\s*=\s*"([^"]+)"/);
          if (nameMatch) ctx.branch = nameMatch[1];
        }
      } catch (e) {}
      if (!ctx.branch) ctx.branch = 'GitButler workspace';
    } else {
      try {
        ctx.branch = execFileSync('git', ['branch', '--show-current'], { cwd: cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
      } catch (e) {}
      if (!ctx.branch) {
        try {
          ctx.branch = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
        } catch (e) {}
      }
    }

    ctx.projectName = path.basename(cwd);
  } catch (e) {}

  return ctx;
}

const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.map': 'application/json',
};

function serveFile(res, filePath) {
  const ext = path.extname(filePath);
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  try {
    const content = fs.readFileSync(filePath);
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  } catch (err) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString()));
    req.on('error', reject);
  });
}

// Return true iff `candidate` is contained within `root` (both resolved absolute paths).
// Uses path.sep suffix to avoid the classic prefix-match bug where /proj matches /proj-evil.
function isWithin(root, candidate) {
  var normRoot = path.resolve(root);
  var normCandidate = path.resolve(candidate);
  if (normCandidate === normRoot) return true;
  var rootWithSep = normRoot.endsWith(path.sep) ? normRoot : normRoot + path.sep;
  return normCandidate.startsWith(rootWithSep);
}

function handleApiFileContext(req, res, url) {
  var filePath = url.searchParams.get('file');
  var startLine = parseInt(url.searchParams.get('start') || '1', 10);
  var endLine = parseInt(url.searchParams.get('end') || '20', 10);

  if (!filePath) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'file parameter required' }));
    return;
  }

  // Lock cwd at server startup. Do NOT trust review-meta.json for this -
  // anyone who can write that file could otherwise redirect reads.
  var cwd = PROJECT_DIR || process.cwd();

  var fullPath = path.resolve(cwd, filePath);
  if (!isWithin(cwd, fullPath)) {
    res.writeHead(403, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Access denied' }));
    return;
  }

  try {
    var content = fs.readFileSync(fullPath, 'utf8');
    var allLines = content.split('\n');
    var lines = allLines.slice(Math.max(0, startLine - 1), endLine);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ file: filePath, startLine: startLine, endLine: endLine, lines: lines, totalLines: allLines.length }));
  } catch (e) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'File not found' }));
  }
}

function handleApiDiff(req, res) {
  const diffPath = path.join(STATE_DIR, 'diff.patch');
  const metaPath = path.join(STATE_DIR, 'review-meta.json');

  let rawDiff = '';
  let meta = {};

  try {
    rawDiff = fs.readFileSync(diffPath, 'utf8');
  } catch (err) {}

  try {
    meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
  } catch (err) {}

  var baseline = meta.baseline || 'HEAD';
  // Git context always comes from the locked PROJECT_DIR, branch info must
  // reflect the server's project, not a meta-file-supplied path.
  var cwd = PROJECT_DIR || process.cwd();
  var gitCtx = getGitContext(cwd);

  if (baseline === 'HEAD') {
    gitCtx.baselineLabel = 'Uncommitted changes';
  } else {
    gitCtx.baselineLabel = 'vs ' + baseline;
  }
  gitCtx.baseline = baseline;

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ baseline: baseline, rawDiff: rawDiff, git: gitCtx, version: SERVER_VERSION }));
}

// Atomic claim: rename review.json to a uniquely-named consumed marker so
// exactly one consumer (long-poll, hook, manual cat) can read it.
function claimReview() {
  const reviewPath = path.join(STATE_DIR, 'review.json');
  const claimPath = path.join(STATE_DIR, '.review.claimed.' + process.pid + '.' + Date.now());
  try {
    fs.renameSync(reviewPath, claimPath);
  } catch (err) {
    return null;
  }
  try {
    const body = fs.readFileSync(claimPath, 'utf8');
    fs.unlinkSync(claimPath);
    return JSON.parse(body);
  } catch (err) {
    try { fs.unlinkSync(claimPath); } catch (e) {}
    return null;
  }
}

async function handleApiReview(req, res) {
  const body = await readBody(req);
  const reviewPath = path.join(STATE_DIR, 'review.json');

  try {
    const review = JSON.parse(body);
    review.timestamp = Date.now();
    fs.writeFileSync(reviewPath, JSON.stringify(review, null, 2));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
  } catch (err) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Invalid JSON' }));
  }
}

function handleApiStatus(req, res) {
  const reviewPath = path.join(STATE_DIR, 'review.json');
  const exists = fs.existsSync(reviewPath);
  let review = null;

  if (exists) {
    try {
      review = JSON.parse(fs.readFileSync(reviewPath, 'utf8'));
    } catch (err) {}
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ submitted: exists, review: review, version: SERVER_VERSION }));
}

// Long-poll: hold the connection open until review.json appears or timeout.
// Atomically claims the file on success so concurrent consumers can't
// double-deliver. If the client disconnects early, the poll timer is cleared
// and the file (if any) is left for the next caller / the hook to handle.
const WAIT_MAX_MS = 9 * 60 * 1000; // 9 min, under typical 10-min client timeouts
const WAIT_POLL_INTERVAL_MS = 500;

function handleApiWaitForReview(req, res) {
  const startedAt = Date.now();
  let poller = null;
  let timedOut = false;

  function cleanup() {
    if (poller) {
      clearInterval(poller);
      poller = null;
    }
  }

  req.on('close', cleanup);

  const immediate = claimReview();
  if (immediate) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ delivered: true, review: immediate }));
    return;
  }

  poller = setInterval(() => {
    lastActivity = Date.now();
    if (Date.now() - startedAt > WAIT_MAX_MS) {
      timedOut = true;
      cleanup();
      if (!res.writableEnded) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ delivered: false, reason: 'timeout' }));
      }
      return;
    }
    const claimed = claimReview();
    if (claimed) {
      cleanup();
      if (!res.writableEnded) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ delivered: true, review: claimed }));
      }
    }
  }, WAIT_POLL_INTERVAL_MS);
}

const server = http.createServer(async (req, res) => {
  lastActivity = Date.now();

  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  // API routes
  if (pathname === '/api/heartbeat' && (req.method === 'GET' || req.method === 'HEAD')) {
    res.writeHead(204);
    res.end();
    return;
  }
  if (pathname === '/api/file-context' && req.method === 'GET') {
    return handleApiFileContext(req, res, url);
  }
  if (pathname === '/api/diff' && req.method === 'GET') {
    return handleApiDiff(req, res);
  }
  if (pathname === '/api/review' && req.method === 'POST') {
    return handleApiReview(req, res);
  }
  if (pathname === '/api/status' && req.method === 'GET') {
    return handleApiStatus(req, res);
  }
  if (pathname === '/api/wait-for-review' && req.method === 'GET') {
    return handleApiWaitForReview(req, res);
  }

  // Static files
  if (pathname === '/' || pathname === '/index.html') {
    return serveFile(res, path.join(UI_DIR, 'index.html'));
  }
  if (pathname === '/styles.css') {
    return serveFile(res, path.join(UI_DIR, 'styles.css'));
  }
  if (pathname === '/app.js') {
    return serveFile(res, path.join(UI_DIR, 'app.js'));
  }
  if (pathname.startsWith('/vendor/')) {
    const vendorPath = path.join(VENDOR_DIR, pathname.slice('/vendor/'.length));
    const resolved = path.resolve(vendorPath);
    if (!isWithin(VENDOR_DIR, resolved)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }
    return serveFile(res, resolved);
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

// Best-effort GC of stale session dirs on startup (sessions dir is sibling of
// SESSION_DIR under <project>/.ds/sessions/). Removes directories older than
// STALE_SESSION_MAX_AGE_MS whose PID is dead.
function sweepStaleSessions() {
  try {
    const sessionsRoot = path.dirname(SESSION_DIR);
    if (!fs.existsSync(sessionsRoot)) return;
    const entries = fs.readdirSync(sessionsRoot);
    const now = Date.now();
    for (const name of entries) {
      const dir = path.join(sessionsRoot, name);
      if (dir === SESSION_DIR) continue;
      let stat;
      try { stat = fs.statSync(dir); } catch (e) { continue; }
      if (!stat.isDirectory()) continue;
      if (now - stat.mtimeMs < STALE_SESSION_MAX_AGE_MS) continue;

      const pidFile = path.join(dir, 'state', 'server.pid');
      let alive = false;
      if (fs.existsSync(pidFile)) {
        try {
          const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
          if (pid > 0) {
            try { process.kill(pid, 0); alive = true; } catch (e) {}
          }
        } catch (e) {}
      }
      if (alive) continue;
      try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
    }
  } catch (e) {}
}

sweepStaleSessions();

server.listen(0, BIND_HOST, () => {
  const addr = server.address();
  const info = {
    type: 'server-started',
    port: addr.port,
    host: BIND_HOST,
    url_host: URL_HOST,
    url: `http://${URL_HOST}:${addr.port}`,
    state_dir: STATE_DIR,
    session_dir: SESSION_DIR,
    version: SERVER_VERSION,
  };

  fs.writeFileSync(path.join(STATE_DIR, 'server-info'), JSON.stringify(info));
  console.log(JSON.stringify(info));
});

if (OWNER_PID > 0) {
  setInterval(() => {
    try {
      process.kill(OWNER_PID, 0);
    } catch (err) {
      process.exit(0);
    }
  }, OWNER_CHECK_INTERVAL_MS);
}

setInterval(() => {
  if (Date.now() - lastActivity > IDLE_TIMEOUT_MS) {
    process.exit(0);
  }
}, 60 * 1000);

process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
});
process.on('SIGINT', () => {
  server.close(() => process.exit(0));
});
