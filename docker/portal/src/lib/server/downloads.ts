// Public files from data/downloads, e.g. plugins and their update manifests (see routes/downloads)
import fs from 'node:fs';
import path from 'node:path';

export const DOWNLOADS_DIR = '/var/www/downloads';
export const DOWNLOAD_TYPES: Record<string, string> = {
	xpi: 'application/x-xpinstall', json: 'application/json', pdf: 'application/pdf',
	txt: 'text/plain; charset=utf-8', png: 'image/png', jpg: 'image/jpeg', svg: 'image/svg+xml',
	zip: 'application/zip'
};

const extension = (file: string) => path.extname(file).slice(1).toLowerCase();

function realpath(p: string): string | null {
	try {
		return fs.realpathSync(p);
	} catch {
		return null;
	}
}

/** Downloadable files below `dir`, relative to DOWNLOADS_DIR, sorted */
export function downloadFiles(dir = ''): string[] {
	const root = realpath(DOWNLOADS_DIR);
	const base = realpath(path.join(DOWNLOADS_DIR, dir));
	if (!root || !base || !fs.statSync(base).isDirectory()) return [];
	const files: string[] = [];
	const walk = (d: string) => {
		for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
			if (entry.name.startsWith('.')) continue;
			const full = path.join(d, entry.name);
			const stat = fs.statSync(full, { throwIfNoEntry: false });
			if (stat?.isDirectory()) walk(full);
			else if (stat?.isFile() && DOWNLOAD_TYPES[extension(entry.name)]) files.push(full.slice(root.length + 1));
		}
	};
	walk(base);
	return files.sort();
}

/** Whether there is anything to download, so login page and menu only link to a non-empty page */
export const hasDownloads = () => downloadFiles().length > 0;

/** The admin's HTML fragment for the downloads page: index.<language>.html, else index.html */
export function downloadsPage(language: string): string | null {
	for (const name of [`index.${language}.html`, 'index.html']) {
		const file = path.join(DOWNLOADS_DIR, name);
		if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8');
	}
	return null;
}

/** Newest file in `dir` by the version number in its name (name-1.2.10.xpi > name-1.2.9.xpi) */
export function latest(dir: string): string | null {
	const version = (f: string) => (/(\d+(?:\.\d+)+)/.exec(path.basename(f))?.[1] ?? '0').split('.').map(Number);
	const compare = (a: number[], b: number[]) => {
		for (let i = 0; i < Math.max(a.length, b.length); i++) {
			if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) - (b[i] ?? 0);
		}
		return 0;
	};
	const candidates = downloadFiles(dir).filter((f) => !f.endsWith('.json'));
	candidates.sort((a, b) => compare(version(b), version(a)));
	return candidates[0] ? path.basename(candidates[0]) : null;
}

/** A regular file of an allowed type inside DOWNLOADS_DIR, no dot files, no "..": path and type */
export function resolveDownload(rel: string): { file: string; ext: string } | null {
	const root = realpath(DOWNLOADS_DIR);
	const file = realpath(path.join(DOWNLOADS_DIR, rel));
	if (!root || !file || !file.startsWith(root + '/') || !fs.statSync(file).isFile()) return null;
	const ext = extension(file);
	if (!DOWNLOAD_TYPES[ext] || file.slice(root.length).includes('/.')) return null;
	return { file, ext };
}
