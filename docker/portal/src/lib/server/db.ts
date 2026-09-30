import mysql from 'mysql2/promise';
import { env } from './config';

let pool: mysql.Pool | undefined;

export function db(): mysql.Pool {
	pool ??= mysql.createPool({
		host: env.MYSQL_HOST || 'mysql',
		user: 'root',
		password: env.MYSQL_ROOT_PASSWORD,
		charset: 'utf8mb4',
		connectionLimit: 5
	});
	return pool;
}

type Row = Record<string, any>;
type Runner = Pick<mysql.Pool, 'execute'>;

export async function all<T = Row>(sql: string, params: unknown[] = [], conn: Runner = db()): Promise<T[]> {
	const [rows] = await conn.execute(sql, params as any[]);
	return rows as T[];
}

export async function row<T = Row>(sql: string, params: unknown[] = [], conn: Runner = db()): Promise<T | null> {
	return (await all<T>(sql, params, conn))[0] ?? null;
}

/** Runs an INSERT/UPDATE/DELETE; returns the insert ID */
export async function exec(sql: string, params: unknown[] = [], conn: Runner = db()): Promise<number> {
	const [result] = await conn.execute(sql, params as any[]);
	return (result as mysql.ResultSetHeader).insertId;
}
