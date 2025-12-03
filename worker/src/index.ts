/**
 * forge-proxy — streams a public workers.dev hostname through to a self-hosted
 * Forgejo instance reachable over a Tailscale Funnel URL.
 *
 * Cloudflare Access sits in front of this Worker and provides the login gate.
 * This Worker's only jobs are:
 *   1. pass git smart-HTTP through *without buffering*,
 *   2. not leak Access identity material to the origin,
 *   3. keep Forgejo's absolute redirects pointing at the public hostname.
 */

const HOP_BY_HOP = [
	'connection',
	'keep-alive',
	'transfer-encoding',
	'te',
	'trailer',
	'upgrade',
	'proxy-authorization',
	'proxy-authenticate',
];

const STRIP_PREFIXES = ['cf-access-', 'cf-visitor'];
const STRIP_EXACT = ['cf-connecting-ip', 'cf-ray', 'cf-ipcountry', 'cf-worker', 'x-real-ip'];

function stripAccessCookie(cookie: string): string | null {
	const kept = cookie
		.split(';')
		.map((c) => c.trim())
		.filter((c) => c.length > 0 && !c.startsWith('CF_Authorization='));
	return kept.length > 0 ? kept.join('; ') : null;
}

function buildOriginHeaders(request: Request, publicHost: string): Headers {
	const headers = new Headers(request.headers);
	for (const name of HOP_BY_HOP) headers.delete(name);
	headers.delete('host');
	for (const name of [...headers.keys()]) {
		if (STRIP_PREFIXES.some((p) => name.startsWith(p)) || STRIP_EXACT.includes(name)) {
			headers.delete(name);
		}
	}
	const cookie = request.headers.get('cookie');
	if (cookie) {
		const remaining = stripAccessCookie(cookie);
		if (remaining) headers.set('cookie', remaining);
		else headers.delete('cookie');
	}
	headers.set('x-forwarded-proto', 'https');
	headers.set('x-forwarded-host', publicHost);
	const clientIp = request.headers.get('cf-connecting-ip');
	if (clientIp) headers.set('x-forwarded-for', clientIp);
	return headers;
}

function rewriteLocation(location: string, originUrl: URL, publicOrigin: string): string {
	try {
		const target = new URL(location, originUrl);
		if (target.host === originUrl.host) {
			return publicOrigin + target.pathname + target.search + target.hash;
		}
		return location;
	} catch {
		return location;
	}
}

export default {
	async fetch(request, env): Promise<Response> {
		const incoming = new URL(request.url);
		let origin: URL;
		try {
			origin = new URL(env.FORGE_ORIGIN);
		} catch {
			console.error(JSON.stringify({ msg: 'FORGE_ORIGIN is not a valid URL', value: env.FORGE_ORIGIN }));
			return Response.json({ error: 'proxy misconfigured' }, { status: 500 });
		}
		const originUrl = new URL(incoming.pathname + incoming.search, origin);
		const originRequest = new Request(originUrl, {
			method: request.method,
			headers: buildOriginHeaders(request, incoming.host),
			body: request.body,
			redirect: 'manual',
		});
		let originResponse: Response;
		try {
			originResponse = await fetch(originRequest, {
				cf: { cacheEverything: false, cacheTtl: 0 },
			});
		} catch (err) {
			console.error(
				JSON.stringify({
					msg: 'origin unreachable',
					origin: origin.host,
					path: incoming.pathname,
					error: err instanceof Error ? err.message : String(err),
				}),
			);
			return Response.json(
				{ error: 'forge origin unreachable', hint: 'is the Tailscale Funnel up on the forge host?' },
				{ status: 502 },
			);
		}
		const headers = new Headers(originResponse.headers);
		for (const name of HOP_BY_HOP) headers.delete(name);
		const location = headers.get('location');
		if (location) {
			headers.set('location', rewriteLocation(location, originUrl, incoming.origin));
		}
		const contentType = headers.get('content-type') ?? '';
		if (contentType.startsWith('application/x-git-')) {
			headers.set('cache-control', 'no-store, max-age=0');
			headers.delete('etag');
		}
		return new Response(originResponse.body, {
			status: originResponse.status,
			statusText: originResponse.statusText,
			headers,
		});
	},
};
