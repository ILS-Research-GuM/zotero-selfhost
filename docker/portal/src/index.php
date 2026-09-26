<?php
// Keycloak login in front of the web-library and the desktop client's browser login
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/Accounts.php';

use Jumbojett\OpenIDConnectClient;

$baseURL = rtrim(getenv('WEB_LIBRARY_URL'), '/');
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

session_set_cookie_params(['secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
session_name('zotero_portal');
session_start();

function oidc(): OpenIDConnectClient {
	global $baseURL;
	$oidc = new OpenIDConnectClient(getenv('OIDC_ISSUER'), getenv('OIDC_CLIENT_ID'), getenv('OIDC_CLIENT_SECRET'));
	$oidc->setRedirectURL("$baseURL/oidc/callback");
	$oidc->addScope(['openid', 'email', 'profile']);
	return $oidc;
}

function page(string $title, string $body, int $status = 200): never {
	http_response_code($status);
	header('Content-Type: text/html; charset=utf-8');
	header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'");
	$t = htmlspecialchars($title);
	echo "<!DOCTYPE html><html lang=\"de\"><head><meta charset=\"utf-8\"><title>$t</title>"
		. '<meta name="viewport" content="width=device-width, initial-scale=1">'
		. '<style>body{font:16px/1.5 system-ui,sans-serif;max-width:32rem;margin:4rem auto;padding:0 1rem;color:#222}'
		. 'button{font:inherit;padding:.5rem 1.2rem;margin-right:.5rem;cursor:pointer}'
		. '@media(prefers-color-scheme:dark){body{background:#1e1e1e;color:#ddd}}</style>'
		. "</head><body><h1>$t</h1>$body</body></html>";
	exit;
}

/**
 * Redirects to Keycloak. Each pending login keeps its own state, nonce and return target,
 * so several tabs or reloads during login don't invalidate each other.
 */
function startLogin(string $returnTo): never {
	$discovery = json_decode(@file_get_contents(rtrim(getenv('OIDC_ISSUER'), '/') . '/.well-known/openid-configuration'), true);
	if (empty($discovery['authorization_endpoint'])) {
		error_log('OIDC discovery failed');
		page('Anmeldung nicht verfügbar', '<p>Der Anmeldedienst ist gerade nicht erreichbar.</p>', 503);
	}
	$pending = array_filter($_SESSION['oidcPending'] ?? [], fn($p) => $p['time'] > time() - 900);
	$pending = array_slice($pending, -9, null, true);
	$state = bin2hex(random_bytes(16));
	$nonce = bin2hex(random_bytes(16));
	$pending[$state] = ['nonce' => $nonce, 'returnTo' => $returnTo, 'time' => time()];
	$_SESSION['oidcPending'] = $pending;
	global $baseURL;
	header('Location: ' . $discovery['authorization_endpoint'] . '?' . http_build_query([
		'response_type' => 'code',
		'client_id' => getenv('OIDC_CLIENT_ID'),
		'redirect_uri' => "$baseURL/oidc/callback",
		'scope' => 'openid email profile',
		'state' => $state,
		'nonce' => $nonce
	]));
	exit;
}

if ($path === '/favicon.ico') {
	http_response_code(204);
	exit;
}

// Return from Keycloak
if ($path === '/oidc/callback') {
	$state = (string) ($_GET['state'] ?? '');
	$pending = $_SESSION['oidcPending'][$state] ?? null;
	if (!$pending) {
		error_log('OIDC callback with unknown state');
		page('Anmeldung abgelaufen', '<p>Die Anmeldung ist abgelaufen oder wurde in einem anderen Fenster abgeschlossen. <a href="/">Erneut anmelden</a></p>', 400);
	}
	unset($_SESSION['oidcPending'][$state]);
	$_SESSION['returnTo'] = $pending['returnTo'];
	try {
		$oidc = oidc();
		// The library checks state and nonce against these session keys
		$_SESSION['openid_connect_state'] = $state;
		$_SESSION['openid_connect_nonce'] = $pending['nonce'];
		$oidc->authenticate();
		$claims = $oidc->getVerifiedClaims();
		$_SESSION['user'] = [
			'sub' => $claims->sub,
			'username' => $claims->preferred_username ?? '',
			'email' => $claims->email ?? ''
		];
		$_SESSION['idToken'] = $oidc->getIdToken();
	}
	catch (Throwable $e) {
		error_log("OIDC login failed: " . $e->getMessage());
		page('Anmeldung fehlgeschlagen', '<p>Die Anmeldung über Keycloak ist fehlgeschlagen. <a href="/">Erneut versuchen</a></p>', 401);
	}
	session_regenerate_id(true);
	$returnTo = $_SESSION['returnTo'] ?? '/';
	unset($_SESSION['returnTo']);
	header('Location: ' . $baseURL . $returnTo);
	exit;
}

if ($path === '/logout') {
	$idToken = $_SESSION['idToken'] ?? null;
	session_destroy();
	if ($idToken) {
		oidc()->signOut($idToken, "$baseURL/");
	}
	header("Location: $baseURL/");
	exit;
}

// Everything else requires a Keycloak login
if (empty($_SESSION['user'])) {
	// Only page loads start a login, not background requests
	if (isset($_SERVER['HTTP_SEC_FETCH_MODE']) && $_SERVER['HTTP_SEC_FETCH_MODE'] !== 'navigate') {
		http_response_code(401);
		exit;
	}
	// Keep only same-site paths as return target
	$uri = $_SERVER['REQUEST_URI'];
	startLogin(str_starts_with($uri, '/') && !str_starts_with($uri, '//') ? $uri : '/');
}

$accounts = new Accounts();
$u = $_SESSION['user'];
$user = $accounts->getOrCreateUser($u['sub'], $u['username'], $u['email']);
$name = htmlspecialchars($user['username']);

// Desktop client login: Zotero opens /login?session=<token> in the browser
if ($path === '/login') {
	$token = $_REQUEST['session'] ?? '';
	if (!preg_match('/^[A-Za-z0-9]{1,64}$/', $token)) {
		page('Ungültiger Link', '<p>Dieser Anmeldelink ist ungültig.</p>', 400);
	}
	[$status, $info] = Api::request('GET', "keys/sessions/$token/info", null, true);
	if ($status == 410 || $status == 404 || ($info['status'] ?? '') !== 'pending') {
		page('Link abgelaufen', '<p>Dieser Anmeldelink ist abgelaufen oder wurde schon verwendet. Starte die Anmeldung in Zotero neu.</p>', 410);
	}
	// A client that was linked to an account before may only log in to that account again
	if (!empty($info['userID']) && (int) $info['userID'] !== (int) $user['userID']) {
		page('Anderes Konto', '<p>Dieses Zotero ist mit einem anderen Konto verbunden. Melde dich bei Keycloak mit diesem Konto an oder setze die Verknüpfung in Zotero zurück.</p>', 403);
	}

	if ($_SERVER['REQUEST_METHOD'] === 'POST') {
		if (!hash_equals($_SESSION['csrf'][$token] ?? '', $_POST['csrf'] ?? '')) {
			page('Anfrage abgelehnt', '<p>Die Bestätigung war ungültig. Öffne den Link aus Zotero erneut.</p>', 403);
		}
		unset($_SESSION['csrf'][$token]);
		if (($_POST['action'] ?? '') !== 'allow') {
			Api::request('DELETE', "keys/sessions/$token");
			page('Abgebrochen', '<p>Zotero wurde nicht verbunden. Du kannst dieses Fenster schließen.</p>');
		}
		[$status] = Api::request('POST', 'keys/sessions/complete', [
			'sessionToken' => $token,
			'userID' => (int) $user['userID'],
			'access' => Accounts::FULL_ACCESS
		], true);
		if ($status != 204) {
			error_log("Completing login session failed: $status");
			page('Fehler', '<p>Zotero konnte nicht verbunden werden. Starte die Anmeldung in Zotero neu.</p>', 500);
		}
		page('Zotero ist verbunden', "<p>Zotero synchronisiert jetzt mit dem Konto <b>$name</b>. Du kannst dieses Fenster schließen und zu Zotero zurückkehren.</p>");
	}

	// Explicit confirmation, so a login link sent by someone else can't take over the account
	$_SESSION['csrf'][$token] = bin2hex(random_bytes(16));
	$csrf = $_SESSION['csrf'][$token];
	$client = htmlspecialchars($info['clientType'] ?? 'Zotero');
	page('Zotero verbinden', "<p>Soll <b>$client</b> auf deinem Gerät Zugriff auf deine Zotero-Bibliothek (Konto <b>$name</b>) bekommen?</p>"
		. '<p>Bestätige nur, wenn du die Anmeldung gerade selbst in Zotero gestartet hast.</p>'
		. '<form method="post"><input type="hidden" name="session" value="' . htmlspecialchars($token) . '">'
		. '<input type="hidden" name="csrf" value="' . $csrf . '">'
		. '<button name="action" value="allow">Verbinden</button><button name="action" value="deny">Abbrechen</button></form>');
}

// web-library, configured for this user
$config = [
	'userId' => (string) $user['userID'],
	'userSlug' => $user['username'],
	'apiKey' => $accounts->getWebLibraryKey($user['userID']),
	'apiConfig' => [
		'apiScheme' => getenv('API_SCHEME'),
		'apiAuthorityPart' => getenv('API_AUTHORITY'),
		'retry' => 2
	],
	'websiteUrl' => "$baseURL/",
	'streamingApiUrl' => getenv('STREAMING_URL'),
	'libraries' => ['includeMyLibrary' => true, 'includeUserGroups' => true]
];
$menu = [
	'desktop' => [
		['label' => 'My Library', 'href' => '/', 'active' => true],
		['label' => $user['username'], 'dropdown' => true, 'truncate' => true, 'entries' => [['label' => 'Abmelden', 'href' => '/logout']]]
	],
	'mobile' => [
		['label' => 'My Library', 'href' => '/', 'active' => true],
		['label' => 'Abmelden', 'href' => '/logout']
	]
];
$json = fn($v) => json_encode($v, JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP);
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
echo str_replace(['{{CONFIG}}', '{{MENU}}'], [$json($config), $json($menu)], file_get_contents(__DIR__ . '/web-library.html'));
