#!/usr/bin/env node
/**
 * Loop heartbeat for the Google VPS (runs right after nightscout-librelink-up).
 *
 * After LibreLinkUp has uploaded the new reading to Nightscout, this sends a push
 * notification (APNs) to Loop on the iPhone. The patched Loop build treats it like a
 * pump heartbeat: it wakes up, reads the new value from Nightscout and loops.
 *
 * No npm packages needed (uses Node's built-in http2 and crypto).
 *
 *   node loop-heartbeat.js            normal run (called from the cron wrapper)
 *   node loop-heartbeat.js --check    show config, latest reading, device token; send nothing
 *   node loop-heartbeat.js --test     send one heartbeat now and print Apple's answer
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const http2 = require('http2');

// =============================== CONFIGURATION ===============================
const CONFIG = {
  nsUrl:        'https://nsval.mooo.com',
  nsToken:      process.env.NS_READ_TOKEN || '',   // Nightscout access token (readable), plain text, not hashed

  apnsKeyFile:  path.join(__dirname, 'AuthKey_CH9BGBJ8YT.p8'),
  apnsKeyId:    'CH9BGBJ8YT',
  teamId:       'YYYYYYYYYY',                      // your Apple Team ID (same as on WHC)

  deviceToken:  '',   // '' = read from Nightscout profile (loopSettings.deviceToken)
  bundleId:     '',   // '' = read from Nightscout profile (loopSettings.bundleIdentifier)

  apnsEnv:      'production',                      // TestFlight builds = production
  mode:         'passive',                         // 'passive' or 'background' (same meaning as on WHC)

  // LibreView gives a reading every minute; Loop loops every ~5 min. 4.83 = 4 min 50 s: Loop starts a
  // new loop only when the last is over 4.2 min old, so closer pushes can wake it without a loop.
  minGapMin:    4.83,
  sourceName:   'vps', // sent with each push, shown in Loop's log: "Remote heartbeat push did fire (from vps)"
  maxAgeMin:    6,    // don't wake Loop for a reading older than this
  keepaliveMin: 10,   // also push if nothing was sent for this long, even with no new reading (0 = off)
};
// ============================================================================

const STATE_FILE = path.join(__dirname, 'heartbeat-state.json');
const LOG_FILE   = path.join(__dirname, 'heartbeat.log');
const args = process.argv.slice(2);
const VERBOSE = args.includes('--check') || args.includes('--test') || args.includes('--verbose');

function log(msg) {
  const line = `${new Date().toISOString().replace('T', ' ').slice(0, 19)}  ${msg}\n`;
  if (VERBOSE) process.stdout.write(line);
  try {
    if (fs.existsSync(LOG_FILE) && fs.statSync(LOG_FILE).size > 200000) {
      fs.writeFileSync(LOG_FILE, fs.readFileSync(LOG_FILE, 'utf8').slice(-100000));
    }
    fs.appendFileSync(LOG_FILE, line);
  } catch (_) {}
}

function loadState() {
  try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch (_) { return {}; }
}
function saveState(s) { fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2)); }

// Plain http/https GET (works on Node 12+; no fetch needed).
function nsGet(p) {
  const url = new URL(CONFIG.nsUrl.replace(/\/$/, '') + p);
  if (CONFIG.nsToken) url.searchParams.set('token', CONFIG.nsToken);
  const lib = url.protocol === 'http:' ? require('http') : require('https');
  return new Promise((resolve) => {
    const req = lib.get(url, { headers: { Accept: 'application/json' }, timeout: 15000 }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        if (res.statusCode !== 200) { log(`Nightscout ${p} failed: HTTP ${res.statusCode}`); return resolve(null); }
        try { resolve(JSON.parse(body)); } catch (_) { log(`Nightscout ${p}: not JSON`); resolve(null); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (e) => { log(`Nightscout ${p} failed: ${e.message}`); resolve(null); });
  });
}

async function latestReading() {
  const e = await nsGet('/api/v1/entries/sgv.json?count=1');
  return e && e[0] && e[0].date ? { date: Number(e[0].date), sgv: e[0].sgv } : null;
}

async function loopTarget(state) {
  if (CONFIG.deviceToken && CONFIG.bundleId) return [CONFIG.deviceToken, CONFIG.bundleId];
  const fresh = state.token && state.bundle && Date.now() / 1000 - (state.tokenChecked || 0) < 3600;
  if (!fresh) {
    const p = await nsGet('/api/v1/profile.json?count=1');
    const ls = (p && p[0] && p[0].loopSettings) || {};
    if (ls.deviceToken && ls.bundleIdentifier) {
      if (state.token !== ls.deviceToken) log(`Device token from Nightscout profile: ${ls.deviceToken.slice(0, 8)}…`);
      state.token = ls.deviceToken;
      state.bundle = ls.bundleIdentifier;
      state.tokenChecked = Math.floor(Date.now() / 1000);
    }
  }
  return [CONFIG.deviceToken || state.token || '', CONFIG.bundleId || state.bundle || ''];
}

const b64url = (b) => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function apnsJwt(state) {
  const now = Math.floor(Date.now() / 1000);
  if (state.jwt && now - (state.jwtIat || 0) < 3000) return state.jwt;   // reuse for 50 min
  let key;
  try { key = fs.readFileSync(CONFIG.apnsKeyFile, 'utf8'); }
  catch (_) { log(`Cannot read APNs key file ${CONFIG.apnsKeyFile}`); return null; }
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: CONFIG.apnsKeyId }));
  const claims = b64url(JSON.stringify({ iss: CONFIG.teamId, iat: now }));
  const sig = crypto.sign('sha256', Buffer.from(`${header}.${claims}`), { key, dsaEncoding: 'ieee-p1363' });
  state.jwt = `${header}.${claims}.${b64url(sig)}`;
  state.jwtIat = now;
  return state.jwt;
}

function apnsPost(host, headers, body) {
  return new Promise((resolve) => {
    const client = http2.connect(`https://${host}`);
    let status = 0, data = '';
    const done = (r) => { try { client.close(); } catch (_) {} resolve(r); };
    client.on('error', (e) => done({ status: 0, body: e.message }));
    const req = client.request({ ':method': 'POST', ':path': headers.path, ...headers.h });
    req.setTimeout(15000, () => { req.close(); done({ status: 0, body: 'timeout' }); });
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (c) => { data += c; });
    req.on('end', () => done({ status, body: data }));
    req.on('error', (e) => done({ status: 0, body: e.message }));
    req.end(body);
  });
}

async function sendHeartbeat(state, reason) {
  const [token, bundle] = await loopTarget(state);
  if (!token || !bundle) { log('No device token / bundle id (check Loop uploads to Nightscout)'); return false; }
  const jwt = apnsJwt(state);
  if (!jwt) return false;

  const passive = CONFIG.mode === 'passive';
  const aps = { 'content-available': 1 };
  if (passive) {
    aps.alert = { title: 'Loop', body: 'Checking for new glucose data' };
    aps['interruption-level'] = 'passive';
    aps['thread-id'] = 'loop-heartbeat';
  }
  const payload = JSON.stringify({ aps, 'loop-heartbeat': 1, from: CONFIG.sourceName || 'vps', sent: Math.floor(Date.now() / 1000) });
  const host = CONFIG.apnsEnv === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';

  const r = await apnsPost(host, {
    path: `/3/device/${token}`,
    h: {
      authorization: `bearer ${jwt}`,
      'apns-topic': bundle,
      'apns-push-type': passive ? 'alert' : 'background',
      'apns-priority': passive ? '10' : '5',
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 240),
      'apns-collapse-id': 'loop-heartbeat',
      'content-type': 'application/json',
    },
  }, payload);

  if (r.status === 200) {
    state.lastPush = Math.floor(Date.now() / 1000);
    log(`Heartbeat sent (${reason}, ${CONFIG.mode})`);
    return true;
  }
  log(`APNs error: HTTP ${r.status} ${r.body}`);
  if (r.status === 403) delete state.jwt;
  if ((r.status === 400 || r.status === 410) && /Token/.test(r.body)) { delete state.token; delete state.tokenChecked; }
  return false;
}

(async () => {
  const state = loadState();

  if (args.includes('--check')) {
    const r = await latestReading();
    console.log(`Nightscout:  ${CONFIG.nsUrl}`);
    console.log(`Latest SGV:  ${r ? `${r.sgv} at ${new Date(r.date).toLocaleString()}` : 'none'}`);
    const [t, b] = await loopTarget(state);
    console.log(`Bundle id:   ${b || 'NOT FOUND'}`);
    console.log(`Token:       ${t ? t.slice(0, 12) + '…' : 'NOT FOUND'}`);
    console.log(`APNs key:    ${fs.existsSync(CONFIG.apnsKeyFile) ? 'found' : 'MISSING'}`);
    let jwt = null;
    try { jwt = apnsJwt(state); } catch (e) { log(`JWT error: ${e.message}`); }
    console.log(`JWT:         ${jwt ? 'OK' : 'FAILED'}`);
    saveState(state);
    return;
  }

  if (args.includes('--test')) {
    await sendHeartbeat(state, 'manual test');
    saveState(state);
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  const sinceLastMin = (now - (state.lastPush || 0)) / 60;
  const r = await latestReading();

  if (r) {
    const ageMin = (Date.now() - r.date) / 60000;
    const isNew = r.date > (state.lastDate || 0);
    if (isNew && ageMin <= CONFIG.maxAgeMin && sinceLastMin >= CONFIG.minGapMin) {
      if (await sendHeartbeat(state, `new reading ${r.sgv}`)) state.lastDate = r.date;
    } else if (CONFIG.keepaliveMin > 0 && sinceLastMin >= CONFIG.keepaliveMin) {
      await sendHeartbeat(state, 'keep-alive');
    }
  } else if (CONFIG.keepaliveMin > 0 && sinceLastMin >= CONFIG.keepaliveMin) {
    await sendHeartbeat(state, 'keep-alive (Nightscout unreachable)');
  }
  saveState(state);
})();
