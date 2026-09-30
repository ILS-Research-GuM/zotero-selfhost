//   /downloads/<dir>/latest   redirect to the newest file in <dir> (by version in the file name)
//   /downloads/<path>         the file itself
import fs from 'node:fs';
import { Readable } from 'node:stream';
import { redirect } from '@sveltejs/kit';
import { config } from '$lib/server/config';
import { DOWNLOAD_TYPES, latest, resolveDownload } from '$lib/server/downloads';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = ({ params, locals }) => {
	const notFound = () => new Response(locals.t('This download does not exist.'), {
		status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' }
	});
	const dir = /^([A-Za-z0-9._-]+)\/latest$/.exec(params.path)?.[1];
	if (dir) {
		const file = latest(dir);
		if (!file) return notFound();
		redirect(302, `${config.baseURL}/downloads/${dir}/${encodeURIComponent(file)}`);
	}
	const found = resolveDownload(params.path);
	if (!found) return notFound();
	const { file, ext } = found;
	const headers: Record<string, string> = {
		'Content-Type': DOWNLOAD_TYPES[ext],
		'Content-Length': String(fs.statSync(file).size),
		'X-Content-Type-Options': 'nosniff',
		'Cache-Control': ext === 'json' ? 'no-cache' : 'public, max-age=300'
	};
	if (ext !== 'json' && ext !== 'txt') headers['Content-Disposition'] = `attachment; filename="${file.split('/').pop()}"`;
	return new Response(Readable.toWeb(fs.createReadStream(file)) as ReadableStream, { headers });
};
