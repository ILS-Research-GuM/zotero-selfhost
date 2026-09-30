// OIDC login chosen on the sign-in page
import { error } from '@sveltejs/kit';
import { config } from '$lib/server/config';
import { oidcLogin } from '$lib/server/oidc';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
	if (!config.useOIDC) error(404, { message: locals.t('This page does not exist.') });
	await oidcLogin(locals.session, locals.session.data.returnTo ?? '/', locals.t);
};
