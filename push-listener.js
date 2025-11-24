// Listens for Forgejo "push" webhooks and runs ./forge.sh push (encrypt + upload
// to Backblaze B2) in the background. One push at a time; a push that arrives
// mid-run is coalesced into a single follow-up run instead of piling up.
'use strict';
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const FORGE_DIR = __dirname;
const ENV_FILE = path.join(FORGE_DIR, '.forge-env');
const LOG_FILE = path.join(FORGE_DIR, 'push-listener.log');
const PORT = 9988;

function readEnvVar(name) {
    const line = fs.readFileSync(ENV_FILE, 'utf8')
        .split('\n')
        .find((l) => l.startsWith(name + '='));
    if (!line) throw new Error(`${name} not set in .forge-env`);
    return line.slice(name.length + 1).trim();
}

const SECRET = readEnvVar('WEBHOOK_SECRET');

function log(msg) {
    const line = `[${new Date().toISOString()}] ${msg}\n`;
    process.stdout.write(line);
    fs.appendFileSync(LOG_FILE, line);
}

let running = false;
let queued = false;

function runPush() {
    if (running) {
        queued = true;
        log('push already running, queuing another run');
        return;
    }
    running = true;
    log('running forge.sh push');
    const proc = spawn('bash', ['forge.sh', 'push', '--yes'], {
        cwd: FORGE_DIR,
        env: { ...process.env, FORGE_ASSUME_YES: '1' },
    });
    proc.stdout.on('data', (d) => fs.appendFileSync(LOG_FILE, d));
    proc.stderr.on('data', (d) => fs.appendFileSync(LOG_FILE, d));
    proc.on('close', (code) => {
        log(`forge.sh push exited with code ${code}`);
        running = false;
        if (queued) {
            queued = false;
            runPush();
        }
    });
}

function verifySignature(body, signatureHeader) {
    if (!signatureHeader) return false;
    const expected = crypto.createHmac('sha256', SECRET).update(body).digest('hex');
    const a = Buffer.from(expected, 'utf8');
    const b = Buffer.from(signatureHeader, 'utf8');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const server = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/hook') {
        res.writeHead(404);
        res.end();
        return;
    }
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
        const body = Buffer.concat(chunks);
        const sig = req.headers['x-forgejo-signature'] || req.headers['x-gitea-signature'] || req.headers['x-hub-signature-256'];
        if (!verifySignature(body, sig)) {
            log('rejected webhook: bad signature');
            res.writeHead(401);
            res.end();
            return;
        }
        res.writeHead(200);
        res.end('ok');
        let payload = {};
        try { payload = JSON.parse(body.toString('utf8')); } catch { /* ignore */ }
        log(`push received: ${payload.repository?.full_name || 'unknown'} -> ${payload.ref || '?'}`);
        runPush();
    });
});

server.listen(PORT, '0.0.0.0', () => {
    log(`push-listener up on :${PORT}`);
});
