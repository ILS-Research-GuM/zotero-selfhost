// Login in front of the web-library and the desktop client's browser login: an OIDC provider
// (e.g. Keycloak) if OIDC_ISSUER is set, username and password of the Zotero account if
// PASSWORD_LOGIN is on (default: only without OIDC), or both side by side
import { isHttpError, type Handle } from '@sveltejs/kit';
import { config, env } from '$lib/server/config';
import { Session } from '$lib/server/session';
import { pickLanguage, translator } from '$lib/i18n';
import { safeReturnTo, startLogin } from '$lib/server/login';
import { getOrCreateUser } from '$lib/server/accounts';

const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'";

/** Paths reachable without a login */
function isPublic(path: string): boolean {
	return (config.useOIDC && (path === '/oidc/start' || path === '/oidc/callback'))
		|| (config.passwordLogin && path === '/signin')
		|| path === '/logout'
		// Public on purpose: Zotero checks plugin updates without a session
		|| path === '/downloads' || path.startsWith('/downloads/');
}

export const handle: Handle = async ({ event, resolve }) => {
	// Forms are plain HTML posts. Kit answers posts without "Accept: text/html" (e.g. from scripts)
	// with JSON meant for its client-side forms, which the portal doesn't use.
	const accept = event.request.headers.get('accept') ?? '';
	if (event.request.method === 'POST' && !accept.includes('text/html') && !event.url.pathname.startsWith('/translate/')) {
		event.request.headers.set('accept', 'text/html');
	}
	const { url, request, cookies } = event;
	if (url.pathname === '/favicon.ico') return new Response(null, { status: 204 });

	const picked = (url.searchParams.get('lang') ?? '').toLowerCase();
	const language = pickLanguage(picked, cookies.get('zotero_portal_lang') ?? '', env.PORTAL_LANGUAGE ?? '',
		request.headers.get('accept-language') ?? '');
	if (picked === language) {
		cookies.set('zotero_portal_lang', language, {
			path: '/', maxAge: 365 * 86400, httpOnly: true, sameSite: 'lax', secure: config.secureCookies
		});
	}
	event.locals.language = language;
	event.locals.t = translator(language);
	const session = (event.locals.session = new Session(cookies));

	if (!isPublic(url.pathname)) {
		const sessionUser = session.data.user;
		if (!sessionUser) {
			// Only page loads start a login, not background requests
			const mode = request.headers.get('sec-fetch-mode');
			if (mode !== null && mode !== 'navigate') return new Response(null, { status: 401 });
			try {
				await startLogin(session, safeReturnTo(url.pathname + url.search), event.locals.t);
			} catch (e) {
				if (isHttpError(e)) return new Response(e.body.message, { status: e.status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
				throw e;
			}
		}
		// Password logins already know the Zotero user; OIDC logins are mapped (and created on first login)
		const u = sessionUser!;
		u.userID ??= (await getOrCreateUser(u.sub!, u.username, u.email ?? '')).userID;
		event.locals.user = { userID: u.userID, username: u.username };
	}

	const response = await resolve(event, { transformPageChunk: ({ html }) => html.replace('%lang%', language) });
	// Portal pages; the web-library page loads its own scripts
	if (event.route.id !== '/[...rest]' && response.headers.get('content-type')?.startsWith('text/html')) {
		response.headers.set('Content-Security-Policy', CSP);
	}
	return response;
};

// Unexpected errors: log them, show a generic page
export const handleError: import('@sveltejs/kit').HandleServerError = ({ error, event, status }) => {
	if (status >= 500) console.error(error);
	const t = event.locals.t ?? ((s: string) => s);
	return status === 404
		? { title: t('Not found'), message: t('This page does not exist.') }
		: { title: t('Error'), message: t('Something went wrong. Please try again later.') };
};
