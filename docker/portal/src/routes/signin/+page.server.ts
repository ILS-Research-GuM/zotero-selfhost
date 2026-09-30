// Sign-in page with the password form, and a button for the OIDC login if both are on
import { error, fail, redirect } from '@sveltejs/kit';
import { setTimeout as sleep } from 'node:timers/promises';
import { config } from '$lib/server/config';
import { token } from '$lib/server/session';
import { verifyPassword } from '$lib/server/accounts';
import { hasDownloads } from '$lib/server/downloads';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = ({ locals }) => {
	if (!config.passwordLogin) error(404, { message: locals.t('This page does not exist.') });
	locals.session.data.signinCsrf ??= token();
	return {
		csrf: locals.session.data.signinCsrf,
		oidcLabel: config.useOIDC ? config.oidcLabel : null,
		hasDownloads: hasDownloads()
	};
};

export const actions: Actions = {
	default: async ({ request, locals }) => {
		const { session, t } = locals;
		const form = await request.formData();
		if (!session.data.signinCsrf || form.get('csrf') !== session.data.signinCsrf) {
			error(403, { title: t('Request rejected'), message: t('The form was invalid.'), link: { href: '/signin', label: t('Try again') } });
		}
		const user = await verifyPassword(String(form.get('username') ?? ''), String(form.get('password') ?? ''));
		if (!user) {
			// Slow down password guessing
			await sleep(2000);
			return fail(401, { wrongPassword: true });
		}
		const returnTo = session.data.returnTo ?? '/';
		session.regenerate();
		delete session.data.signinCsrf;
		delete session.data.returnTo;
		session.data.user = user;
		redirect(302, config.baseURL + returnTo);
	}
};
