// Downloads: public files from data/downloads, e.g. plugins and their update manifests. Public on
// purpose: Zotero checks plugin updates without a session. The page is index.<language>.html or
// index.html (an HTML fragment written by the admin), or a plain file list if there is none.
import { downloadFiles, downloadsPage } from '$lib/server/downloads';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = ({ locals }) => ({
	html: downloadsPage(locals.language),
	files: downloadFiles().filter((f) => !/^index(\.[a-z]{2})?\.html$/.test(f))
});
