// Server-side sessions in memory, referenced by a random ID in the zotero_portal cookie. Like the
// PHP sessions before, they end when the portal container restarts; users then log in again.
import { randomBytes } from 'node:crypto';
import type { Cookies } from '@sveltejs/kit';
import { config } from './config';

export type SessionUser = { sub?: string; username: string; email?: string; userID?: number };
type Pending = { nonce: string; returnTo: string; time: number };

export type SessionData = {
	user?: SessionUser;
	returnTo?: string;
	/** Pending OIDC logins by state, so several tabs or reloads during login don't clash */
	oidcPending?: Record<string, Pending>;
	idToken?: string;
	signinCsrf?: string;
	/** CSRF token per desktop client login token */
	loginCsrf?: Record<string, string>;
	groupsCsrf?: string;
	groupsFlash?: { error: boolean; text: string };
};

const COOKIE = 'zotero_portal';
const IDLE_MS = 8 * 3600 * 1000;
const store = new Map<string, { data: SessionData; seen: number }>();
let lastSweep = Date.now();

export const token = () => randomBytes(16).toString('hex');

export class Session {
	id: string;
	data: SessionData;

	constructor(private cookies: Cookies) {
		const now = Date.now();
		if (now - lastSweep > 600_000) {
			lastSweep = now;
			for (const [id, s] of store) if (now - s.seen > IDLE_MS) store.delete(id);
		}
		const id = cookies.get(COOKIE) ?? '';
		const existing = store.get(id);
		if (existing && now - existing.seen <= IDLE_MS) {
			existing.seen = now;
			this.id = id;
			this.data = existing.data;
		} else {
			this.id = '';
			this.data = {};
			this.start();
		}
	}

	private start() {
		this.id = randomBytes(24).toString('base64url');
		store.set(this.id, { data: this.data, seen: Date.now() });
		this.cookies.set(COOKIE, this.id, { path: '/', httpOnly: true, sameSite: 'lax', secure: config.secureCookies });
	}

	/** New ID for the same data, after a login (prevents session fixation) */
	regenerate() {
		store.delete(this.id);
		this.start();
	}

	destroy() {
		store.delete(this.id);
		this.data = {};
		this.cookies.delete(COOKIE, { path: '/', secure: config.secureCookies });
	}
}
