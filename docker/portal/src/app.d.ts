import type { Session } from '$lib/server/session';
import type { Translator } from '$lib/i18n';

declare global {
	namespace App {
		interface Error {
			title?: string;
			message: string;
			/** Optional link below the message, e.g. "Try again" */
			link?: { href: string; label: string };
		}
		interface Locals {
			session: Session;
			language: string;
			t: Translator;
			/** Zotero account of the logged-in user; set for every route behind the login */
			user?: { userID: number; username: string };
			/** Set by the desktop client login form, so the page shows the outcome */
			loginOutcome?: 'cancelled' | 'connected';
		}
		interface PageData {
			language: string;
			languages: string[];
			path: string;
		}
	}
}

export {};
