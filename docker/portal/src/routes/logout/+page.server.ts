import { redirect } from '@sveltejs/kit';
import { config } from '$lib/server/config';
import { endSessionURL } from '$lib/server/oidc';
import type { PageServerLoad } from './$types';

// Ends the portal session and, after an OIDC login, the provider's session too
export const load: PageServerLoad = async ({ locals }) => {
	const idToken = locals.session.data.idToken;
	locals.session.destroy();
	const providerLogout = idToken && config.useOIDC ? await endSessionURL(idToken) : null;
	redirect(302, providerLogout ?? `${config.baseURL}/`);
};
