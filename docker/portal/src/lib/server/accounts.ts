// Maps OIDC users to Zotero users and API keys, creating them on first login, and checks
// passwords for the login without OIDC
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import net from 'node:net';
import bcrypt from 'bcryptjs';
import { all, db, exec, row } from './db';
import { api } from './api';
import { env } from './config';

export type Account = { userID: number; username: string };

export const FULL_ACCESS = {
	user: { library: true, files: true, notes: true, write: true },
	groups: { all: { library: true, write: true } }
};

/** The Zotero account for the OIDC user, creating it if needed */
export async function getOrCreateUser(sub: string, preferredUsername: string, email: string): Promise<Account> {
	const linked = await row<Account>(
		`SELECT u.userID, u.username FROM zotero_www.users_meta m JOIN zotero_www.users u USING (userID)
			WHERE m.metaKey = 'oidcSub' AND m.metaValue = ?`, [sub]);
	if (linked) return { userID: Number(linked.userID), username: linked.username };

	const conn = await db().getConnection();
	try {
		await conn.beginTransaction();
		// Link an existing local account with the same email that isn't linked yet
		let user = email === '' ? null : await row<Account>(
			`SELECT u.userID, u.username FROM zotero_www.users u JOIN zotero_www.users_email e USING (userID)
				WHERE e.email = ? AND NOT EXISTS (SELECT 1 FROM zotero_www.users_meta m
					WHERE m.userID = u.userID AND m.metaKey = 'oidcSub')
				LIMIT 1`, [email], conn);
		user ??= await createUser(conn, await freeUsername(preferredUsername || email || sub), email);
		await exec(`INSERT INTO zotero_www.users_meta (userID, metaKey, metaValue) VALUES (?, 'oidcSub', ?)`, [user.userID, sub], conn);
		await claimSharedGroup(conn, Number(user.userID), email);
		await conn.commit();
		return { userID: Number(user.userID), username: user.username };
	} catch (e) {
		await conn.rollback();
		throw e;
	} finally {
		conn.release();
	}
}

const sameText = (a: string, b: string) => {
	const x = Buffer.from(a), y = Buffer.from(b);
	return x.length === y.length && timingSafeEqual(x, y);
};

/**
 * Checks a username or email and password like the dataserver does (bcrypt, salted SHA1 or MD5
 * from older installations)
 */
export async function verifyPassword(login: string, password: string): Promise<Account | null> {
	if (login === '' || password === '') return null;
	const rows = await all<Account & { password: string }>(
		`SELECT u.userID, u.username, u.password FROM zotero_www.users u WHERE u.username = ?
		UNION SELECT u.userID, u.username, u.password FROM zotero_www.users u JOIN zotero_www.users_email e USING (userID)
			WHERE e.email = ?`, [login, login]);
	const salt = env.ZOTERO_AUTH_SALT ?? '';
	const sha1 = createHash('sha1').update(salt + password).digest('hex');
	const md5 = createHash('md5').update(password).digest('hex');
	for (const r of rows) {
		const hash = String(r.password);
		// PHP writes bcrypt as $2y$, the same algorithm as $2b$
		const bcryptOK = /^\$2[aby]\$/.test(hash) && (await bcrypt.compare(password, hash.replace(/^\$2y\$/, '$2b$')));
		if (bcryptOK || sameText(hash, sha1) || sameText(hash, md5)) {
			return { userID: Number(r.userID), username: r.username };
		}
	}
	return null;
}

/** API key the web-library uses for this user, created on first use */
export async function getWebLibraryKey(userID: number): Promise<string> {
	const key = (await row(`SELECT metaValue FROM zotero_www.users_meta WHERE userID = ? AND metaKey = 'webLibraryKey'`, [userID]))?.metaValue;
	if (key && (await api('GET', `keys/${key}`))[0] === 200) return key;
	const [status, json] = await api('POST', `users/${userID}/keys`, { name: 'web-library', access: FULL_ACCESS }, true);
	if (status !== 201) throw new Error(`Creating web-library key failed: ${status}`);
	await exec(`REPLACE INTO zotero_www.users_meta (userID, metaKey, metaValue) VALUES (?, 'webLibraryKey', ?)`, [userID, json.key]);
	return json.key;
}

type Conn = Parameters<typeof exec>[2];

/**
 * Hands the shared group over to the SHARED_GROUP_OWNER user on their first login, if
 * apply-shared-group.sh couldn't because they didn't exist yet. Like Zotero_Group::save(), the
 * previous owner becomes admin. Happens once; later changes to the group are kept.
 */
async function claimSharedGroup(conn: Conn, userID: number, email: string) {
	const groupID = await sharedGroupID(conn);
	const pending = groupID ? await setting(conn, 'sharedGroupPendingOwner') : null;
	if (!pending || email === '' || pending.toLowerCase() !== email.toLowerCase()) return;
	await exec(`DELETE FROM zotero_selfhost.settings WHERE name = 'sharedGroupPendingOwner'`, [], conn);
	await exec(`UPDATE zotero_master.groupUsers SET role = 'admin' WHERE groupID = ? AND role = 'owner' AND userID != ?`, [groupID, userID], conn);
	await exec(`INSERT INTO zotero_master.groupUsers (groupID, userID, role, joined) VALUES (?, ?, 'owner', CURRENT_TIMESTAMP)
		ON DUPLICATE KEY UPDATE role = 'owner', lastUpdated = CURRENT_TIMESTAMP`, [groupID, userID], conn);
	// The dataserver caches the owner in memcached under its API URL as key prefix
	const prefix = (env.ZOTERO_API_URL ?? '').replace(/\/+$/, '') + '/';
	await memcachedDelete(`${prefix}groupData_${groupID}`);
}

function memcachedDelete(key: string): Promise<void> {
	return new Promise((resolve) => {
		const socket = net.connect({ host: 'memcached', port: 11211, timeout: 2000 });
		const done = () => { socket.destroy(); resolve(); };
		socket.on('connect', () => socket.write(`delete ${key}\r\n`));
		socket.on('data', done);
		socket.on('timeout', done);
		socket.on('error', done);
	});
}

/** ID of the group every user joins (set up by apply-shared-group.sh), or null */
async function sharedGroupID(conn?: Conn): Promise<number | null> {
	const id = await setting(conn, 'sharedGroupID');
	return id ? Number(id) : null;
}

async function setting(conn: Conn, name: string): Promise<string | null> {
	try {
		return (await row(`SELECT value FROM zotero_selfhost.settings WHERE name = ?`, [name], conn))?.value ?? null;
	} catch {
		// The table exists once a shared group was set up
		return null;
	}
}

async function createUser(conn: Conn, username: string, email: string): Promise<Account> {
	// Password login isn't used for OIDC accounts, so set an unguessable one
	const hash = await bcrypt.hash(randomBytes(32).toString('hex'), 10);
	const userID = await exec(`INSERT INTO zotero_www.users (username, password) VALUES (?, ?)`, [username, hash], conn);
	if (email !== '') await exec(`INSERT INTO zotero_www.users_email (userID, email) VALUES (?, ?)`, [userID, email], conn);
	const libraryID = await exec(`INSERT INTO zotero_master.libraries (libraryType, shardID) VALUES ('user', 1)`, [], conn);
	await exec(`INSERT INTO zotero_master.users (userID, libraryID, username) VALUES (?, ?, ?)`, [userID, libraryID, username], conn);
	await exec(`INSERT INTO zotero_shard_1.shardLibraries (libraryID, libraryType) VALUES (?, 'user')`, [libraryID], conn);
	await exec(`INSERT INTO zotero_master.storageAccounts (userID, quota, expiration) VALUES (?, ?, '2038-01-01 00:00:00')`,
		[userID, Number(env.ZOTERO_STORAGE_QUOTA_MB) || 1000000], conn);
	// Same as bin/create-user.sh: new users join the shared group as members, if there is one
	const groupID = await sharedGroupID(conn);
	if (groupID) {
		await exec(`INSERT INTO zotero_master.groupUsers (groupID, userID, role, joined) VALUES (?, ?, 'member', CURRENT_TIMESTAMP)`, [groupID, userID], conn);
	}
	return { userID, username };
}

async function freeUsername(wanted: string): Promise<string> {
	const base = wanted.split('@')[0].replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 36) || 'user';
	let name = base;
	for (let i = 2; await row(`SELECT 1 FROM zotero_www.users WHERE username = ?`, [name]); i++) name = `${base}${i}`;
	return name;
}
