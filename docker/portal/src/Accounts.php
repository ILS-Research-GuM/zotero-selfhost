<?php
// Maps Keycloak users to Zotero users and API keys, creating them on first login

class Accounts {
	private mysqli $db;

	const FULL_ACCESS = [
		'user' => ['library' => true, 'files' => true, 'notes' => true, 'write' => true],
		'groups' => ['all' => ['library' => true, 'write' => true]]
	];

	public function __construct() {
		mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
		$this->db = new mysqli(getenv('MYSQL_HOST') ?: 'mysql', 'root', getenv('MYSQL_ROOT_PASSWORD'));
		$this->db->set_charset('utf8mb4');
	}

	/**
	 * Returns ['userID' => ..., 'username' => ...] for the Keycloak user, creating it if needed
	 */
	public function getOrCreateUser(string $sub, string $preferredUsername, string $email): array {
		$user = $this->row(
			"SELECT u.userID, u.username FROM zotero_www.users_meta m JOIN zotero_www.users u USING (userID)
				WHERE m.metaKey = 'keycloakSub' AND m.metaValue = ?", [$sub]);
		if ($user) {
			return $user;
		}

		$this->db->begin_transaction();
		try {
			// Link an existing local account with the same email that isn't linked yet
			$user = $email === '' ? null : $this->row(
				"SELECT u.userID, u.username FROM zotero_www.users u JOIN zotero_www.users_email e USING (userID)
					WHERE e.email = ? AND NOT EXISTS (SELECT 1 FROM zotero_www.users_meta m
						WHERE m.userID = u.userID AND m.metaKey = 'keycloakSub')
					LIMIT 1", [$email]);
			if (!$user) {
				$user = $this->createUser($this->freeUsername($preferredUsername ?: $email ?: $sub), $email);
			}
			$this->query("INSERT INTO zotero_www.users_meta (userID, metaKey, metaValue) VALUES (?, 'keycloakSub', ?)",
				[$user['userID'], $sub]);
			$this->db->commit();
		}
		catch (Throwable $e) {
			$this->db->rollback();
			throw $e;
		}
		return $user;
	}

	/**
	 * API key the web-library uses for this user, created on first use
	 */
	public function getWebLibraryKey(int $userID): string {
		$key = $this->row("SELECT metaValue FROM zotero_www.users_meta WHERE userID = ? AND metaKey = 'webLibraryKey'",
			[$userID])['metaValue'] ?? null;
		if ($key) {
			[$status] = Api::request('GET', "keys/$key");
			if ($status == 200) {
				return $key;
			}
		}
		[$status, $json] = Api::request('POST', "users/$userID/keys",
			['name' => 'web-library', 'access' => self::FULL_ACCESS], true);
		if ($status != 201) {
			throw new Exception("Creating web-library key failed: $status");
		}
		$this->query("REPLACE INTO zotero_www.users_meta (userID, metaKey, metaValue) VALUES (?, 'webLibraryKey', ?)",
			[$userID, $json['key']]);
		return $json['key'];
	}

	private function createUser(string $username, string $email): array {
		// Password login isn't used for Keycloak accounts, so set an unguessable one
		$hash = password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT);
		$this->query("INSERT INTO zotero_www.users (username, password) VALUES (?, ?)", [$username, $hash]);
		$userID = $this->db->insert_id;
		if ($email !== '') {
			$this->query("INSERT INTO zotero_www.users_email (userID, email) VALUES (?, ?)", [$userID, $email]);
		}
		$this->query("INSERT INTO zotero_master.libraries (libraryType, shardID) VALUES ('user', 1)");
		$libraryID = $this->db->insert_id;
		$this->query("INSERT INTO zotero_master.users (userID, libraryID, username) VALUES (?, ?, ?)",
			[$userID, $libraryID, $username]);
		$this->query("INSERT INTO zotero_shard_1.shardLibraries (libraryID, libraryType) VALUES (?, 'user')", [$libraryID]);
		$this->query("INSERT INTO zotero_master.storageAccounts (userID, quota, expiration) VALUES (?, ?, '2038-01-01 00:00:00')",
			[$userID, (int) (getenv('ZOTERO_STORAGE_QUOTA_MB') ?: 1000000)]);
		// Same as bin/create-user.sh: new users join group 1 (DEFAULT_GROUP_NAME) as members
		$this->query("INSERT INTO zotero_master.groupUsers (groupID, userID, role, joined)
			SELECT 1, ?, 'member', CURRENT_TIMESTAMP FROM zotero_master.`groups` WHERE groupID = 1", [$userID]);
		return ['userID' => $userID, 'username' => $username];
	}

	private function freeUsername(string $wanted): string {
		$base = substr(preg_replace('/[^A-Za-z0-9._-]/', '_', explode('@', $wanted)[0]), 0, 36) ?: 'user';
		$name = $base;
		for ($i = 2; $this->row("SELECT 1 FROM zotero_www.users WHERE username = ?", [$name]); $i++) {
			$name = "$base$i";
		}
		return $name;
	}

	private function query(string $sql, array $params = []) {
		$stmt = $this->db->prepare($sql);
		$stmt->execute($params);
		return $stmt->get_result();
	}

	private function row(string $sql, array $params = []): ?array {
		$result = $this->query($sql, $params);
		return $result ? $result->fetch_assoc() : null;
	}
}

// Internal dataserver API, as super user for the website-only endpoints
class Api {
	public static function request(string $method, string $path, ?array $body = null, bool $super = false): array {
		$ch = curl_init('http://dataserver-internal/' . $path);
		$headers = ['Zotero-API-Version: 3'];
		if ($body !== null) {
			$headers[] = 'Content-Type: application/json';
			curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
		}
		curl_setopt_array($ch, [
			CURLOPT_CUSTOMREQUEST => $method,
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_HTTPHEADER => $headers,
			CURLOPT_TIMEOUT => 15
		]);
		if ($super) {
			curl_setopt($ch, CURLOPT_USERPWD, getenv('ZOTERO_SUPER_USER') . ':' . getenv('ZOTERO_SUPER_PASSWORD'));
		}
		$response = curl_exec($ch);
		if ($response === false) {
			throw new Exception('dataserver request failed: ' . curl_error($ch));
		}
		return [curl_getinfo($ch, CURLINFO_RESPONSE_CODE), json_decode($response, true)];
	}
}
