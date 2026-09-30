// Login with an OIDC provider (e.g. Keycloak), authorization code flow with state and nonce
import * as client from 'openid-client';
import { error, redirect } from '@sveltejs/kit';
import { config, env } from './config';
import { token, type Session, type SessionUser } from './session';
import type { Translator } from '$lib/i18n';

let discovered: { at: number; config: Promise<client.Configuration> } | undefined;

/** Provider configuration, discovered once an hour; a failed discovery is retried on the next login */
function provider(): Promise<client.Configuration> {
	if (!discovered || Date.now() - discovered.at > 3600_000) {
		const issuer = new URL(env.OIDC_ISSUER!);
		const promise = client.discovery(issuer, env.OIDC_CLIENT_ID!, env.OIDC_CLIENT_SECRET!, undefined,
			issuer.protocol === 'http:' ? { execute: [client.allowInsecureRequests] } : undefined);
		discovered = { at: Date.now(), config: promise };
		promise.catch(() => { discovered = undefined; });
	}
	return discovered.config;
}

const callbackURL = () => `${config.baseURL}/oidc/callback`;

/**
 * Redirects to the OIDC provider. Each pending login keeps its own state, nonce and return target,
 * so several tabs or reloads during login don't invalidate each other.
 */
export async function oidcLogin(session: Session, returnTo: string, t: Translator): Promise<never> {
	let conf: client.Configuration;
	try {
		conf = await provider();
	} catch (e) {
		console.error('OIDC discovery failed:', (e as Error).message);
		error(503, { message: t('The login service is not reachable right now.') });
	}
	const now = Date.now() / 1000;
	const pending = Object.entries(session.data.oidcPending ?? {}).filter(([, p]) => p.time > now - 900).slice(-9);
	const state = token();
	const nonce = token();
	session.data.oidcPending = Object.fromEntries([...pending, [state, { nonce, returnTo, time: now }]]);
	redirect(302, client.buildAuthorizationUrl(conf, {
		redirect_uri: callbackURL(),
		scope: 'openid email profile',
		state,
		nonce
	}));
}

/** Completes the login on return from the provider; returns the user and the ID token */
export async function oidcCallback(search: string, state: string, nonce: string): Promise<{ user: SessionUser; idToken?: string }> {
	const conf = await provider();
	const tokens = await client.authorizationCodeGrant(conf, new URL(callbackURL() + search),
		{ expectedState: state, expectedNonce: nonce, idTokenExpected: true });
	const claims = tokens.claims()!;
	return {
		user: {
			sub: claims.sub,
			username: String(claims.preferred_username ?? ''),
			email: String(claims.email ?? '')
		},
		idToken: tokens.id_token
	};
}

/** Where to send the browser to end the provider session too, or null */
export async function endSessionURL(idToken: string): Promise<string | null> {
	try {
		const conf = await provider();
		if (!conf.serverMetadata().end_session_endpoint) return null;
		return client.buildEndSessionUrl(conf, { id_token_hint: idToken, post_logout_redirect_uri: `${config.baseURL}/` }).href;
	} catch {
		return null;
	}
}
