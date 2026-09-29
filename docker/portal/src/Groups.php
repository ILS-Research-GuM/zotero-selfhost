<?php
// Group management for logged-in users. Reads come from the database; every change goes through
// the dataserver's super-user API, which also clears its caches. The API trusts the super user, so
// the permission checks for the acting user happen here.
//
// Rules: every user can create groups and leave groups they don't own. Owner and admins add
// members and remove or edit plain members. Only the owner manages admins, changes the settings,
// hands the group over and deletes it.

class Groups {
	const EDITING = ['members', 'admins'];

	private mysqli $db;

	public function __construct() {
		mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
		$this->db = new mysqli(getenv('MYSQL_HOST') ?: 'mysql', 'root', getenv('MYSQL_ROOT_PASSWORD'));
		$this->db->set_charset('utf8mb4');
	}

	/** Groups of the user with their role and member count, by name */
	public function forUser(int $userID): array {
		return $this->all(
			"SELECT g.groupID, g.name, g.description, g.libraryEditing, gu.role,
				(SELECT COUNT(*) FROM zotero_master.groupUsers c WHERE c.groupID = g.groupID) AS members
			FROM zotero_master.groupUsers gu JOIN zotero_master.`groups` g USING (groupID)
			WHERE gu.userID = ? ORDER BY g.name", [$userID]);
	}

	/** The group with the user's role, or null if the user isn't a member */
	public function get(int $groupID, int $userID): ?array {
		return $this->row(
			"SELECT g.*, gu.role FROM zotero_master.`groups` g
				JOIN zotero_master.groupUsers gu ON gu.groupID = g.groupID AND gu.userID = ?
			WHERE g.groupID = ?", [$userID, $groupID]);
	}

	/** Members: owner first, then admins, then members, each by name */
	public function members(int $groupID): array {
		return $this->all(
			"SELECT gu.userID, u.username, gu.role FROM zotero_master.groupUsers gu
				JOIN zotero_www.users u USING (userID)
			WHERE gu.groupID = ? ORDER BY FIELD(gu.role, 'owner', 'admin', 'member'), u.username", [$groupID]);
	}

	/** Usernames of all accounts, for picking a colleague */
	public function usernames(): array {
		return array_column($this->all("SELECT username FROM zotero_www.users ORDER BY username"), 'username');
	}

	/** Account by exact username or email (case-insensitive), or null */
	public function findUser(string $login): ?array {
		$login = trim($login);
		if ($login === '') {
			return null;
		}
		return $this->row(
			"SELECT u.userID, u.username FROM zotero_www.users u WHERE u.username = ?
			UNION SELECT u.userID, u.username FROM zotero_www.users u JOIN zotero_www.users_email e USING (userID)
				WHERE e.email = ?
			LIMIT 1", [$login, $login]);
	}

	/** Creates a private group owned by the user; returns its ID */
	public function create(int $ownerID, string $name, string $description, string $editing): int {
		[$status, $body] = Api::request('POST', 'groups', self::groupXML($ownerID, $name, $description, $editing), true);
		if ($status != 201 || !preg_match('#<zapi:groupID>(\d+)</zapi:groupID>#', (string) $body, $m)) {
			throw new Exception("Creating group failed: $status");
		}
		return (int) $m[1];
	}

	/** Changes name, description and who may edit; owner and privacy stay */
	public function update(array $group, string $name, string $description, string $editing): void {
		$this->expect(Api::request('PUT', "groups/{$group['groupID']}",
			self::groupXML((int) $this->ownerID($group['groupID']), $name, $description, $editing), true), 200);
	}

	/** Adds a member, or sets the role: member, admin or owner (the old owner becomes admin) */
	public function setRole(int $groupID, int $userID, string $role): void {
		$this->expect(Api::request('PUT', "groups/$groupID/users/$userID",
			'<user role="' . htmlspecialchars($role, ENT_XML1) . '"/>', true), 200);
	}

	public function remove(int $groupID, int $userID): void {
		$this->expect(Api::request('DELETE', "groups/$groupID/users/$userID", null, true), 204);
	}

	public function delete(int $groupID): void {
		$this->expect(Api::request('DELETE', "groups/$groupID", null, true), 204);
	}

	/**
	 * Name, description and editing setting from a form, or an error text. Errors are English
	 * base texts for t().
	 */
	public static function validate(array $post): array {
		$name = trim(preg_replace('/\s+/u', ' ', (string) ($post['name'] ?? '')));
		$description = trim((string) ($post['description'] ?? ''));
		$editing = (string) ($post['editing'] ?? '');
		if ($name === '' || mb_strlen($name) > 100) {
			return ['error' => 'The name must have 1 to 100 characters.'];
		}
		if (mb_strlen($description) > 1000) {
			return ['error' => 'The description can have at most 1000 characters.'];
		}
		if (!in_array($editing, self::EDITING, true)) {
			return ['error' => 'The form was invalid.'];
		}
		return ['name' => $name, 'description' => $description, 'editing' => $editing];
	}

	/**
	 * Private group: only members see it. $editing decides who may change items and files: all
	 * members or only owner and admins (like bin/create-group.sh).
	 */
	private static function groupXML(int $ownerID, string $name, string $description, string $editing): string {
		$x = fn($s) => htmlspecialchars($s, ENT_XML1 | ENT_QUOTES);
		return '<group owner="' . $ownerID . '" name="' . $x($name) . '" type="Private" libraryReading="members"'
			. ' libraryEditing="' . $x($editing) . '" fileEditing="' . $x($editing) . '">'
			. '<description>' . $x($description) . '</description><url></url></group>';
	}

	private function ownerID(int $groupID): ?int {
		$id = $this->row("SELECT userID FROM zotero_master.groupUsers WHERE groupID = ? AND role = 'owner'", [$groupID])['userID'] ?? null;
		return $id === null ? null : (int) $id;
	}

	private function expect(array $response, int $status): void {
		if ($response[0] != $status) {
			throw new Exception("Group request failed: {$response[0]} " . substr((string) $response[1], 0, 200));
		}
	}

	private function all(string $sql, array $params = []): array {
		$stmt = $this->db->prepare($sql);
		$stmt->execute($params);
		return $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
	}

	private function row(string $sql, array $params = []): ?array {
		return $this->all($sql, $params)[0] ?? null;
	}
}
