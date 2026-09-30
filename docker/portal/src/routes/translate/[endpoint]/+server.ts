// Translation server for "Add by identifier" and URLs in the web-library. Proxied, so only
// logged-in users can make it fetch URLs, and no reverse proxy route is needed.
import type { RequestHandler } from './$types';

const ENDPOINTS = ['web', 'search', 'import', 'export'];
const MAX_BODY = 10 * 1024 * 1024;

export const POST: RequestHandler = async ({ params, request, url }) => {
	if (!ENDPOINTS.includes(params.endpoint)) return new Response(null, { status: 404 });
	const body = new Uint8Array(await request.arrayBuffer()).slice(0, MAX_BODY);
	let response: Response;
	try {
		response = await fetch(`http://translation-server:1969/${params.endpoint}${url.search}`, {
			method: 'POST',
			headers: { 'Content-Type': request.headers.get('content-type') ?? 'text/plain' },
			body,
			signal: AbortSignal.timeout(60_000)
		});
	} catch (e) {
		console.error('Translation server request failed:', (e as Error).message);
		return new Response(null, { status: 502 });
	}
	return new Response(await response.arrayBuffer(), {
		status: response.status,
		headers: { 'Content-Type': response.headers.get('content-type') || 'application/json', 'Cache-Control': 'no-store' }
	});
};

export const fallback: RequestHandler = () => new Response(null, { status: 404 });
