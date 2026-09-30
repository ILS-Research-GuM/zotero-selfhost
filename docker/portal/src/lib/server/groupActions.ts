// Form actions of the group pages (/settings/groups, /settings/groups/<id>). Every change is a
// POST that redirects back with a message, so reloading the page doesn't repeat it.
import { error, redirect, type RequestEvent } from '@sveltejs/kit';
import * as groups from './groups';
import { config } from './config';
import { token } from './session';
import type { Role } from './groups';
import { roleName, type Translator } from '$lib/i18n';

type Result = [error: boolean, message: string, location: string];
const LIST = '/settings/groups';

/** CSRF token and the message of the last change, for the group pages */
export function pageState(locals: App.Locals) {
	const s = locals.session.data;
	s.groupsCsrf ??= token();
	const flash = s.groupsFlash ?? null;
	delete s.groupsFlash;
	return { csrf: s.groupsCsrf, flash };
}

export async function handleAction(event: RequestEvent, groupID: number | null): Promise<never> {
	const { locals, request } = event;
	const t = locals.t;
	const form = await request.formData();
	if (!locals.session.data.groupsCsrf || form.get('csrf') !== locals.session.data.groupsCsrf) {
		error(403, { title: t('Request rejected'), message: t('The form was invalid.'), link: { href: LIST, label: t('Try again') } });
	}
	const [isError, text, location] = await groupAction(t, locals.user!.userID, groupID, form);
	locals.session.data.groupsFlash = { error: isError, text };
	redirect(303, config.baseURL + location);
}

/** Carries out a form action, checking the acting user's permissions */
async function groupAction(t: Translator, me: number, groupID: number | null, form: FormData): Promise<Result> {
	const action = String(form.get('action') ?? '');
	if (groupID === null) {
		if (action !== 'create') return [true, t('The form was invalid.'), LIST];
		const fields = groups.validate(form);
		if ('error' in fields) return [true, t(fields.error), LIST];
		try {
			const id = await groups.create(me, fields.name, fields.description, fields.editing);
			return [false, t('The group was created. Now add your colleagues.'), `${LIST}/${id}`];
		} catch (e) {
			console.error(e);
			return [true, t('The change could not be saved.'), LIST];
		}
	}

	const here = `${LIST}/${groupID}`;
	const group = await groups.get(groupID, me);
	if (!group) return [true, t('This group does not exist or you are not a member.'), LIST];
	const isOwner = group.role === 'owner';
	const canManage = isOwner || group.role === 'admin';
	const targetID = Number(form.get('user') ?? 0);
	const target = (await groups.members(groupID)).find((m) => m.userID === targetID);
	const denied: Result = [true, t('You are not allowed to do that.'), here];
	const confirmed = form.get('confirm') === '1';

	try {
		switch (action) {
			case 'settings': {
				if (!isOwner) return denied;
				const fields = groups.validate(form);
				if ('error' in fields) return [true, t(fields.error), here];
				await groups.update(group, fields.name, fields.description, fields.editing);
				return [false, t('The settings were saved.'), here];
			}
			case 'add': {
				if (!canManage) return denied;
				const login = String(form.get('login') ?? '').trim();
				const account = await groups.findUser(login);
				if (!account) {
					return [true, t('There is no account %s. Colleagues get an account when they log in for the first time.', login), here];
				}
				if (await groups.get(groupID, account.userID)) return [true, t('%s is already a member.', account.username), here];
				await groups.setRole(groupID, account.userID, 'member');
				return [false, t('%s was added.', account.username), here];
			}
			case 'role': {
				const role = String(form.get('role') ?? '') as Role;
				if (!isOwner || !target || target.role === 'owner' || !['member', 'admin'].includes(role)) return denied;
				await groups.setRole(groupID, targetID, role);
				return [false, t('%s is now %s.', target.username, roleName(t, role)), here];
			}
			case 'remove':
				if (!target || target.role === 'owner' || targetID === me
						|| !(isOwner || (canManage && target.role === 'member'))) return denied;
				await groups.remove(groupID, targetID);
				return [false, t('%s was removed.', target.username), here];
			case 'transfer':
				if (!isOwner || !target || target.role === 'owner' || !confirmed) return denied;
				await groups.setRole(groupID, targetID, 'owner');
				return [false, t('%s is now the owner.', target.username), here];
			case 'leave':
				if (isOwner || !confirmed) return denied;
				await groups.remove(groupID, me);
				return [false, t('You left the group %s.', group.name), LIST];
			case 'delete':
				if (!isOwner || !confirmed) return denied;
				await groups.deleteGroup(groupID);
				return [false, t('The group %s was deleted.', group.name), LIST];
		}
	} catch (e) {
		console.error(e);
		return [true, t('The change could not be saved.'), here];
	}
	return [true, t('The form was invalid.'), here];
}
