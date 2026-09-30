import { redirect } from '@sveltejs/kit';
import { config } from './config';
import { oidcLogin } from './oidc';
import type { Session } from './session';
import type { Translator } from '$lib/i18n';

/**
 * Redirects to the login: the sign-in page if password login is on (it also offers the OIDC
 * login), otherwise straight to the OIDC provider
 */
export async function startLogin(session: Session, returnTo: string, t: Translator): Promise<never> {
	if (config.passwordLogin) {
		session.data.returnTo = returnTo;
		redirect(302, `${config.baseURL}/signin`);
	}
	return oidcLogin(session, returnTo, t);
}

/** Keeps only same-site paths as return target */
export function safeReturnTo(target: string | undefined): string {
	return target && target.startsWith('/') && !target.startsWith('//') && !target.startsWith('/\\') ? target : '/';
}
