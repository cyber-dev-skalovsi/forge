export default {
	async fetch(request, env): Promise<Response> {
		const incoming = new URL(request.url);
		let origin: URL;
		try {
			origin = new URL(env.FORGE_ORIGIN);
		} catch {
			return Response.json({ error: 'proxy misconfigured' }, { status: 500 });
		}
		const originUrl = new URL(incoming.pathname + incoming.search, origin);
		const originRequest = new Request(originUrl, {
			method: request.method,
			headers: request.headers,
			body: request.body,
			redirect: 'manual',
		});
		const originResponse = await fetch(originRequest);
		return new Response(originResponse.body, {
			status: originResponse.status,
			statusText: originResponse.statusText,
			headers: originResponse.headers,
		});
	},
};
