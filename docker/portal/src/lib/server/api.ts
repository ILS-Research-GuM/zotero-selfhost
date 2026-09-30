// Internal dataserver API, as super user for the website-only endpoints. Object bodies are sent as
// JSON, strings as XML (the group endpoints). Returns the status and the decoded JSON, or the raw
// response if it isn't JSON.
import { env } from './config';

export async function api(method: string, path: string, body: object | string | null = null, superUser = false): Promise<[number, any]> {
	const headers: Record<string, string> = { 'Zotero-API-Version': '3' };
	if (body !== null) headers['Content-Type'] = typeof body === 'string' ? 'text/xml' : 'application/json';
	if (superUser) {
		headers.Authorization = 'Basic ' + Buffer.from(`${env.ZOTERO_SUPER_USER}:${env.ZOTERO_SUPER_PASSWORD}`).toString('base64');
	}
	let response: Response;
	try {
		response = await fetch('http://dataserver-internal/' + path, {
			method,
			headers,
			body: body === null ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
			signal: AbortSignal.timeout(15_000)
		});
	} catch (e) {
		throw new Error(`dataserver request failed: ${(e as Error).message}`);
	}
	const text = await response.text();
	try {
		return [response.status, JSON.parse(text)];
	} catch {
		return [response.status, text];
	}
}
