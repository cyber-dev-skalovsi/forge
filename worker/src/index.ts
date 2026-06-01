/**
 * forge-proxy — streams a public workers.dev hostname through to a self-hosted
 * Forgejo instance reachable over a Tailscale Funnel URL.
 *
 * Cloudflare Access sits in front of this Worker and provides the login gate.
 * This Worker's only jobs are:
 *   1. pass git smart-HTTP through *without buffering* (clone/fetch/push break otherwise),
 *   2. not leak Access identity material to the origin,
 *   3. keep Forgejo's absolute redirects pointing at the public hostname.
 */

// Headers that describe a single connection and must not be relayed onward.
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

// Cloudflare-injected headers. cf-access-* carry the Access JWT and the
// authenticated user's identity; the origin has no business seeing them.
const STRIP_PREFIXES = ['cf-access-', 'cf-visitor'];
const STRIP_EXACT = ['cf-connecting-ip', 'cf-ray', 'cf-ipcountry', 'cf-worker', 'x-real-ip'];

/** Drop the Access session cookie while preserving Forgejo's own cookies. */
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

	// Forgejo needs to know the edge spoke HTTPS, or it will emit http:// URLs
	// and mark session cookies insecure.
	headers.set('x-forwarded-proto', 'https');
	headers.set('x-forwarded-host', publicHost);
	const clientIp = request.headers.get('cf-connecting-ip');
	if (clientIp) headers.set('x-forwarded-for', clientIp);

	return headers;
}

/**
 * Forgejo emits absolute redirects built from ROOT_URL. If ROOT_URL is ever left
 * pointing at the origin, rewrite those back to the public hostname so the
 * browser is not bounced off the Access-protected name mid-login.
 */
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

		// Preserve path and query verbatim — git carries ?service=git-upload-pack here.
		const originUrl = new URL(incoming.pathname + incoming.search, origin);

		const originRequest = new Request(originUrl, {
			method: request.method,
			headers: buildOriginHeaders(request, incoming.host),
			// Streamed straight through. Never buffer: packfiles routinely exceed
			// the 128 MB isolate memory limit, and git expects chunked delivery.
			body: request.body,
			redirect: 'manual',
		});

		let originResponse: Response;
		try {
			originResponse = await fetch(originRequest, {
				// git responses must never be cached; a stale ref advertisement
				// produces corrupt-looking fetches.
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

		// Belt and braces: keep intermediaries off git protocol responses.
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
} satisfies ExportedHandler<Env>;
