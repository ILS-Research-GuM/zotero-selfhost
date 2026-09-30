export function escapeHTML(s: string | number): string {
	return String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

/** Bold, escaped text for placeholders in translated HTML messages */
export const bold = (s: string) => `<b>${escapeHTML(s)}</b>`;
