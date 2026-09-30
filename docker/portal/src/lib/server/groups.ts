// Group management for logged-in users. Reads come from the database; every change goes through
// the dataserver's super-user API, which also clears its caches. The API trusts the super user, so
// the permission checks for the acting user happen here (see routes/settings/groups).
//
// Rules: every user can create groups and leave groups they don't own. Owner and admins add
// members and remove or edit plain members. Only the owner manages admins, changes the settings,
// hands the group over and deletes it.
import { all, row } from './db';
import { api } from './api';
import { escapeHTML } from '../html';

export type Role = 'owner' | 'admin' | 'member';
export type Editing = 'members' | 'admins';
export type Group = { groupID: number; name: string; description: string; libraryEditing: Editing; role: Role };
export type Member = { userID: number; username: string; role: Role };

const EDITING: Editing[] = ['members', 'admins'];

/** Groups of the user with their role and member count, by name */
export async function forUser(userID: number) {
	const rows = await all<Group & { members: number }>(
		`SELECT g.groupID, g.name, g.description, g.libraryEditing, gu.role,
			(SELECT COUNT(*) FROM zotero_master.groupUsers c WHERE c.groupID = g.groupID) AS members
		FROM zotero_master.groupUsers gu JOIN zotero_master.\`groups\` g USING (groupID)
		WHERE gu.userID = ? ORDER BY g.name`, [userID]);
	return rows.map((g) => ({ ...g, groupID: Number(g.groupID), members: Number(g.members) }));
}

/** The group with the user's role, or null if the user isn't a member */
export async function get(groupID: number, userID: number): Promise<Group | null> {
	const g = await row<Group>(
		`SELECT g.groupID, g.name, g.description, g.libraryEditing, gu.role FROM zotero_master.\`groups\` g
			JOIN zotero_master.groupUsers gu ON gu.groupID = g.groupID AND gu.userID = ?
		WHERE g.groupID = ?`, [userID, groupID]);
	return g && { ...g, groupID: Number(g.groupID), description: g.description ?? '' };
}

/** Members: owner first, then admins, then members, each by name */
export async function members(groupID: number): Promise<Member[]> {
	const rows = await all<Member>(
		`SELECT gu.userID, u.username, gu.role FROM zotero_master.groupUsers gu
			JOIN zotero_www.users u USING (userID)
		WHERE gu.groupID = ? ORDER BY FIELD(gu.role, 'owner', 'admin', 'member'), u.username`, [groupID]);
	return rows.map((m) => ({ ...m, userID: Number(m.userID) }));
}

/** Usernames of all accounts, for picking a colleague */
export async function usernames(): Promise<string[]> {
	return (await all<{ username: string }>(`SELECT username FROM zotero_www.users ORDER BY username`)).map((r) => r.username);
}

/** Account by exact username or email (case-insensitive), or null */
export async function findUser(login: string) {
	login = login.trim();
	if (login === '') return null;
	const u = await row<{ userID: number; username: string }>(
		`SELECT u.userID, u.username FROM zotero_www.users u WHERE u.username = ?
		UNION SELECT u.userID, u.username FROM zotero_www.users u JOIN zotero_www.users_email e USING (userID)
			WHERE e.email = ?
		LIMIT 1`, [login, login]);
	return u && { userID: Number(u.userID), username: u.username };
}

/** Creates a private group owned by the user; returns its ID */
export async function create(ownerID: number, name: string, description: string, editing: Editing): Promise<number> {
	const [status, body] = await api('POST', 'groups', groupXML(ownerID, name, description, editing), true);
	const m = /<zapi:groupID>(\d+)<\/zapi:groupID>/.exec(String(body));
	if (status !== 201 || !m) throw new Error(`Creating group failed: ${status}`);
	return Number(m[1]);
}

/** Changes name, description and who may edit; owner and privacy stay */
export async function update(group: Group, name: string, description: string, editing: Editing) {
	const owner = await row(`SELECT userID FROM zotero_master.groupUsers WHERE groupID = ? AND role = 'owner'`, [group.groupID]);
	expect(await api('PUT', `groups/${group.groupID}`, groupXML(Number(owner?.userID), name, description, editing), true), 200);
}

/** Adds a member, or sets the role: member, admin or owner (the old owner becomes admin) */
export async function setRole(groupID: number, userID: number, role: Role) {
	expect(await api('PUT', `groups/${groupID}/users/${userID}`, `<user role="${escapeHTML(role)}"/>`, true), 200);
}

export async function remove(groupID: number, userID: number) {
	expect(await api('DELETE', `groups/${groupID}/users/${userID}`, null, true), 204);
}

export async function deleteGroup(groupID: number) {
	expect(await api('DELETE', `groups/${groupID}`, null, true), 204);
}

/** Name, description and editing setting from a form, or an error (English base text for t()) */
export function validate(form: FormData): { name: string; description: string; editing: Editing } | { error: string } {
	const name = String(form.get('name') ?? '').replace(/\s+/gu, ' ').trim();
	const description = String(form.get('description') ?? '').trim();
	const editing = String(form.get('editing') ?? '') as Editing;
	if (name === '' || [...name].length > 100) return { error: 'The name must have 1 to 100 characters.' };
	if ([...description].length > 1000) return { error: 'The description can have at most 1000 characters.' };
	if (!EDITING.includes(editing)) return { error: 'The form was invalid.' };
	return { name, description, editing };
}

/** Path of the group in the web-library */
export function libraryURL(group: { groupID: number; name: string }): string {
	const slug = group.name.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
	return `/groups/${group.groupID}/${slug}/library`;
}

/**
 * Private group: only members see it. `editing` decides who may change items and files: all
 * members or only owner and admins (like bin/create-group.sh).
 */
function groupXML(ownerID: number, name: string, description: string, editing: Editing): string {
	return `<group owner="${ownerID}" name="${escapeHTML(name)}" type="Private" libraryReading="members"`
		+ ` libraryEditing="${escapeHTML(editing)}" fileEditing="${escapeHTML(editing)}">`
		+ `<description>${escapeHTML(description)}</description><url></url></group>`;
}

function expect([status, body]: [number, any], wanted: number) {
	if (status !== wanted) throw new Error(`Group request failed: ${status} ${String(body).slice(0, 200)}`);
}
