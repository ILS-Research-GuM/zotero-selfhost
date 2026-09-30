// Groups of the user, and a form for a new group. Not under /groups/, which are web-library paths.
import * as groups from '$lib/server/groups';
import { handleAction, pageState } from '$lib/server/groupActions';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => ({
	...pageState(locals),
	groups: (await groups.forUser(locals.user!.userID)).map((g) => ({ ...g, libraryURL: groups.libraryURL(g) }))
});

export const actions: Actions = { default: (event) => handleAction(event, null) };
