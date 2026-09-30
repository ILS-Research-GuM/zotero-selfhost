// Desktop client login: Zotero opens /login?session=<token> in the browser. The user confirms
// explicitly, so a login link sent by someone else can't take over the account.
import { error } from '@sveltejs/kit';
import { api } from '$lib/server/api';
import { FULL_ACCESS } from '$lib/server/accounts';
import { token } from '$lib/server/session';
import type { Actions, PageServerLoad } from './$types';

/** The pending login session behind the token; errors if it is invalid, used or someone else's */
async function pendingLogin(locals: App.Locals, sessionToken: string) {
	const t = locals.t;
	if (!/^[A-Za-z0-9]{1,64}$/.test(sessionToken)) {
		error(400, { title: t('Invalid link'), message: t('This login link is invalid.') });
	}
	const [status, info] = await api('GET', `keys/sessions/${sessionToken}/info`, null, true);
	if (status === 410 || status === 404 || info?.status !== 'pending') {
		error(410, { title: t('Link expired'), message: t('This login link has expired or was already used. Start the login in Zotero again.') });
	}
	// A client that was linked to an account before may only log in to that account again
	if (info.userID && Number(info.userID) !== locals.user!.userID) {
		error(403, { title: t('Different account'), message: t('This Zotero is linked to a different account. Log in with that account or unlink the account in Zotero.') });
	}
	return info as { clientType?: string };
}

export const load: PageServerLoad = async ({ locals, url }) => {
	// After the form was sent the page only shows the outcome
	if (locals.loginOutcome) return { outcome: locals.loginOutcome };
	const sessionToken = url.searchParams.get('session') ?? '';
	const info = await pendingLogin(locals, sessionToken);
	const csrf = token();
	(locals.session.data.loginCsrf ??= {})[sessionToken] = csrf;
	return { sessionToken, csrf, client: info.clientType ?? 'Zotero', username: locals.user!.username };
};

export const actions: Actions = {
	default: async ({ locals, request, url }) => {
		const t = locals.t;
		const form = await request.formData();
		const sessionToken = String(form.get('session') ?? url.searchParams.get('session') ?? '');
		await pendingLogin(locals, sessionToken);
		const expected = locals.session.data.loginCsrf?.[sessionToken];
		if (!expected || form.get('csrf') !== expected) {
			error(403, { title: t('Request rejected'), message: t('The confirmation was invalid. Open the link from Zotero again.') });
		}
		delete locals.session.data.loginCsrf![sessionToken];
		if (form.get('action') !== 'allow') {
			await api('DELETE', `keys/sessions/${sessionToken}`);
			locals.loginOutcome = 'cancelled';
			return;
		}
		const [status] = await api('POST', 'keys/sessions/complete', {
			sessionToken, userID: locals.user!.userID, access: FULL_ACCESS
		}, true);
		if (status !== 204) {
			console.error(`Completing login session failed: ${status}`);
			error(500, { title: t('Error'), message: t('Zotero could not be connected. Start the login in Zotero again.') });
		}
		locals.loginOutcome = 'connected';
	}
};
