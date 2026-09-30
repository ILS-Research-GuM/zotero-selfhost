// Return from the OIDC provider
import { error, redirect } from '@sveltejs/kit';
import { config } from '$lib/server/config';
import { oidcCallback } from '$lib/server/oidc';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { session, t } = locals;
	if (!config.useOIDC) error(404, { message: t('This page does not exist.') });
	const state = url.searchParams.get('state') ?? '';
	const pending = session.data.oidcPending?.[state];
	if (!pending) {
		console.error('OIDC callback with unknown state');
		error(400, {
			title: t('Login expired'), message: t('The login has expired or was completed in another window.'),
			link: { href: '/', label: t('Log in again') }
		});
	}
	delete session.data.oidcPending![state];
	let result;
	try {
		result = await oidcCallback(url.search, state, pending.nonce);
	} catch (e) {
		console.error('OIDC login failed:', (e as Error).message);
		error(401, { title: t('Login failed'), message: t('The login failed.'), link: { href: '/', label: t('Try again') } });
	}
	session.regenerate();
	session.data.user = result.user;
	session.data.idToken = result.idToken;
	redirect(302, config.baseURL + pending.returnTo);
};
