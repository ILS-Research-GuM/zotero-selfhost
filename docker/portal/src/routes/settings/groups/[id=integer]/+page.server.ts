// One group: members, adding colleagues, settings, handing over, deleting or leaving
import { error } from '@sveltejs/kit';
import * as groups from '$lib/server/groups';
import { handleAction, pageState } from '$lib/server/groupActions';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, params }) => {
	const t = locals.t;
	const state = pageState(locals);
	const group = await groups.get(Number(params.id), locals.user!.userID);
	if (!group) {
		error(404, {
			title: t('Not found'), message: t('This group does not exist or you are not a member.'),
			link: { href: '/settings/groups', label: t('Groups') }
		});
	}
	const canManage = group.role === 'owner' || group.role === 'admin';
	return {
		...state,
		group: { ...group, libraryURL: groups.libraryURL(group) },
		me: locals.user!.userID,
		members: await groups.members(group.groupID),
		usernames: canManage ? await groups.usernames() : []
	};
};

export const actions: Actions = { default: (event) => handleAction(event, Number(event.params.id)) };
