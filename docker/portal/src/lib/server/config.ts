// Settings from the environment (docker-compose.yml passes them to the portal service)
import { env } from '$env/dynamic/private';

const flag = (value: string) => ['1', 'true', 'yes', 'on'].includes(value.trim().toLowerCase());

export const config = {
	get baseURL() { return (env.WEB_LIBRARY_URL ?? '').replace(/\/+$/, ''); },
	get useOIDC() { return (env.OIDC_ISSUER ?? '') !== ''; },
	// Username and password of the Zotero account: on if PASSWORD_LOGIN says so, else only without OIDC
	get passwordLogin() { return (env.PASSWORD_LOGIN ?? '') !== '' ? flag(env.PASSWORD_LOGIN!) : !this.useOIDC; },
	get oidcLabel() { return env.OIDC_LABEL || 'Single Sign-On'; },
	// Secure cookies only work over HTTPS; plain HTTP setups without a reverse proxy need them off
	get secureCookies() { return this.baseURL.startsWith('https:'); }
};

export { env };
