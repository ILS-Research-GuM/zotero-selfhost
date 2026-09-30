// English texts are the base; <language>.ts translate them, keyed by the English text. Add every
// new text to each translation.
import de from './de';

const translations: Record<string, Record<string, string>> = { en: {}, de };

export const languages = Object.keys(translations);
export const languageNames: Record<string, string> = { en: 'English', de: 'Deutsch' };

export type Translator = (text: string, ...args: string[]) => string;

/** Translated text; %s placeholders are filled with the arguments in order */
export function translator(language: string): Translator {
	const table = translations[language] ?? {};
	return (text, ...args) => {
		let i = 0;
		return (table[text] ?? text).replace(/%s/g, () => args[i++] ?? '');
	};
}

/**
 * Picks the language: the one chosen with the switcher (?lang=, remembered in a cookie), else
 * PORTAL_LANGUAGE as the site default, else the browser's Accept-Language, else English.
 */
export function pickLanguage(picked: string, cookie: string, siteDefault: string, acceptLanguage: string): string {
	for (const candidate of [picked, cookie, siteDefault]) {
		if (languages.includes(candidate.toLowerCase())) return candidate.toLowerCase();
	}
	for (const part of acceptLanguage.split(',')) {
		const code = part.split(';')[0].trim().slice(0, 2).toLowerCase();
		if (languages.includes(code)) return code;
	}
	return 'en';
}

export function roleName(t: Translator, role: string): string {
	return ({ owner: t('Owner'), admin: t('Admin'), member: t('Member') } as Record<string, string>)[role] ?? role;
}
