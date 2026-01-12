// Listens for Forgejo "push" webhooks and runs ./forge.sh push (encrypt + upload
// to Backblaze B2) in the background.
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

const SECRET = process.env.WEBHOOK_SECRET || '';

function log(msg) {
    const line = `[${new Date().toISOString()}] ${msg}\n`;
    process.stdout.write(line);
    fs.appendFileSync(LOG_FILE, line);
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
        res.writeHead(200);
        res.end('ok');
        log('push received, running forge.sh push');
        const proc = spawn('bash', ['forge.sh', 'push', '--yes'], { cwd: FORGE_DIR });
        proc.stdout.on('data', (d) => fs.appendFileSync(LOG_FILE, d));
        proc.stderr.on('data', (d) => fs.appendFileSync(LOG_FILE, d));
        proc.on('close', (code) => log(`forge.sh push exited with code ${code}`));
    });
});

server.listen(PORT, '0.0.0.0', () => {
    log(`push-listener up on :${PORT}`);
});
