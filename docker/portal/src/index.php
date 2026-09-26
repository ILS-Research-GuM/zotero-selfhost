<?php
// Login in front of the web-library and the desktop client's browser login: an OIDC provider
// (e.g. Keycloak) if OIDC_ISSUER is set, username and password of the Zotero account if
// PASSWORD_LOGIN is on (default: only without OIDC), or both side by side
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/Accounts.php';

use Jumbojett\OpenIDConnectClient;

$baseURL = rtrim(getenv('WEB_LIBRARY_URL'), '/');
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$useOIDC = getenv('OIDC_ISSUER') != '';
$passwordLogin = getenv('PASSWORD_LOGIN') != ''
	? filter_var(getenv('PASSWORD_LOGIN'), FILTER_VALIDATE_BOOLEAN)
	: !$useOIDC;

// Secure cookies only work over HTTPS; plain HTTP setups without a reverse proxy need them off
// English texts are the base; lang/<language>.php translate them. PORTAL_LANGUAGE forces a
// language, otherwise the browser's Accept-Language decides.
function language(): string {
	$available = array_map(fn($f) => basename($f, '.php'), glob(__DIR__ . '/lang/*.php'));
	$forced = strtolower((string) getenv('PORTAL_LANGUAGE'));
	if ($forced !== '') {
		return in_array($forced, $available) ? $forced : 'en';
	}
	foreach (explode(',', $_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '') as $part) {
		$code = strtolower(substr(trim(explode(';', $part)[0]), 0, 2));
		if ($code === 'en') {
			return 'en';
		}
		if (in_array($code, $available)) {
			return $code;
		}
	}
	return 'en';
}
$language = language();
$translations = $language === 'en' ? [] : require __DIR__ . "/lang/$language.php";

/**
 * Translated text; %s placeholders are filled with the (already escaped) arguments
 */
function t(string $text, string ...$args): string {
	global $translations;
	return vsprintf($translations[$text] ?? $text, $args);
}

session_set_cookie_params(['secure' => str_starts_with($baseURL, 'https:'), 'httponly' => true, 'samesite' => 'Lax']);
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
	global $language;
	echo "<!DOCTYPE html><html lang=\"$language\"><head><meta charset=\"utf-8\"><title>$t</title>"
		. '<meta name="viewport" content="width=device-width, initial-scale=1">'
		. '<style>body{font:16px/1.5 system-ui,sans-serif;max-width:32rem;margin:4rem auto;padding:0 1rem;color:#222}'
		. 'button{font:inherit;padding:.5rem 1.2rem;margin-right:.5rem;cursor:pointer}'
		. '@media(prefers-color-scheme:dark){body{background:#1e1e1e;color:#ddd}}</style>'
		. "</head><body><h1>$t</h1>$body</body></html>";
	exit;
}

/**
 * Redirects to the login: the sign-in page if password login is on (it also offers the OIDC
 * login), otherwise straight to the OIDC provider
 */
function startLogin(string $returnTo): never {
	global $passwordLogin, $baseURL;
	if ($passwordLogin) {
		$_SESSION['returnTo'] = $returnTo;
		header("Location: $baseURL/signin");
		exit;
	}
	oidcLogin($returnTo);
}

/**
 * Redirects to the OIDC provider. Each pending login keeps its own state, nonce and return
 * target, so several tabs or reloads during login don't invalidate each other.
 */
function oidcLogin(string $returnTo): never {
	global $baseURL;
	$discovery = json_decode(@file_get_contents(rtrim(getenv('OIDC_ISSUER'), '/') . '/.well-known/openid-configuration'), true);
	if (empty($discovery['authorization_endpoint'])) {
		error_log('OIDC discovery failed');
		page(t('Login unavailable'), '<p>' . t('The login service is not reachable right now.') . '</p>', 503);
	}
	$pending = array_filter($_SESSION['oidcPending'] ?? [], fn($p) => $p['time'] > time() - 900);
	$pending = array_slice($pending, -9, null, true);
	$state = bin2hex(random_bytes(16));
	$nonce = bin2hex(random_bytes(16));
	$pending[$state] = ['nonce' => $nonce, 'returnTo' => $returnTo, 'time' => time()];
	$_SESSION['oidcPending'] = $pending;
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

// OIDC login chosen on the sign-in page
if ($path === '/oidc/start' && $useOIDC) {
	oidcLogin($_SESSION['returnTo'] ?? '/');
}

// Sign-in page with the password form, and a button for the OIDC login if both are on
if ($path === '/signin' && $passwordLogin) {
	$error = '';
	if ($_SERVER['REQUEST_METHOD'] === 'POST') {
		if (!hash_equals($_SESSION['signinCsrf'] ?? '', $_POST['csrf'] ?? '')) {
			page(t('Request rejected'), '<p>' . t('The form was invalid.') . ' <a href="/signin">' . t('Try again') . '</a></p>', 403);
		}
		$user = (new Accounts())->verifyPassword((string) ($_POST['username'] ?? ''), (string) ($_POST['password'] ?? ''));
		if ($user) {
			session_regenerate_id(true);
			unset($_SESSION['signinCsrf']);
			$_SESSION['user'] = $user;
			$returnTo = $_SESSION['returnTo'] ?? '/';
			unset($_SESSION['returnTo']);
			header('Location: ' . $baseURL . $returnTo);
			exit;
		}
		// Slow down password guessing
		sleep(2);
		http_response_code(401);
		$error = '<p><b>' . t('Wrong username or password.') . '</b></p>';
	}
	$_SESSION['signinCsrf'] = $_SESSION['signinCsrf'] ?? bin2hex(random_bytes(16));
	$oidcButton = !$useOIDC ? '' : '<form action="/oidc/start"><p><button>'
		. t('Log in with %s', htmlspecialchars(getenv('OIDC_LABEL') ?: 'Single Sign-On')) . '</button></p></form><hr>'
		. '<p>' . t('Or with username and password:') . '</p>';
	page(t('Log in'), $oidcButton . $error
		. '<form method="post"><input type="hidden" name="csrf" value="' . $_SESSION['signinCsrf'] . '">'
		. '<p><label>' . t('Username or email') . '<br><input name="username" autocomplete="username" required autofocus></label></p>'
		. '<p><label>' . t('Password') . '<br><input name="password" type="password" autocomplete="current-password" required></label></p>'
		. '<p><button>' . t('Log in') . '</button></p></form>', http_response_code() ?: 200);
}

// Return from the OIDC provider
if ($path === '/oidc/callback' && $useOIDC) {
	$state = (string) ($_GET['state'] ?? '');
	$pending = $_SESSION['oidcPending'][$state] ?? null;
	if (!$pending) {
		error_log('OIDC callback with unknown state');
		page(t('Login expired'), '<p>' . t('The login has expired or was completed in another window.') . ' <a href="/">' . t('Log in again') . '</a></p>', 400);
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
		page(t('Login failed'), '<p>' . t('The login failed.') . ' <a href="/">' . t('Try again') . '</a></p>', 401);
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
	if ($idToken && $useOIDC) {
		oidc()->signOut($idToken, "$baseURL/");
	}
	header("Location: $baseURL/");
	exit;
}

// Everything else requires a login
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

// Translation server for "Add by identifier" and URLs in the web-library. Proxied, so only
// logged-in users can make it fetch URLs, and no reverse proxy route is needed.
if (str_starts_with($path, '/translate/')) {
	$endpoint = substr($path, strlen('/translate/'));
	if (!in_array($endpoint, ['web', 'search', 'import', 'export'], true) || $_SERVER['REQUEST_METHOD'] !== 'POST') {
		http_response_code(404);
		exit;
	}
	$query = $_SERVER['QUERY_STRING'] ?? '';
	$ch = curl_init("http://translation-server:1969/$endpoint" . ($query !== '' ? "?$query" : ''));
	curl_setopt_array($ch, [
		CURLOPT_POST => true,
		CURLOPT_POSTFIELDS => file_get_contents('php://input', false, null, 0, 10 * 1024 * 1024),
		CURLOPT_HTTPHEADER => ['Content-Type: ' . ($_SERVER['CONTENT_TYPE'] ?? 'text/plain')],
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_TIMEOUT => 60
	]);
	$body = curl_exec($ch);
	if ($body === false) {
		error_log('Translation server request failed: ' . curl_error($ch));
		http_response_code(502);
		exit;
	}
	http_response_code(curl_getinfo($ch, CURLINFO_RESPONSE_CODE));
	header('Content-Type: ' . (curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: 'application/json'));
	header('Cache-Control: no-store');
	echo $body;
	exit;
}

$accounts = new Accounts();
$u = $_SESSION['user'];
// Password logins already know the Zotero user; OIDC logins are mapped (and created on first login)
$user = isset($u['userID']) ? $u : $accounts->getOrCreateUser($u['sub'], $u['username'], $u['email']);
$name = htmlspecialchars($user['username']);

// Desktop client login: Zotero opens /login?session=<token> in the browser
if ($path === '/login') {
	$token = $_REQUEST['session'] ?? '';
	if (!preg_match('/^[A-Za-z0-9]{1,64}$/', $token)) {
		page(t('Invalid link'), '<p>' . t('This login link is invalid.') . '</p>', 400);
	}
	[$status, $info] = Api::request('GET', "keys/sessions/$token/info", null, true);
	if ($status == 410 || $status == 404 || ($info['status'] ?? '') !== 'pending') {
		page(t('Link expired'), '<p>' . t('This login link has expired or was already used. Start the login in Zotero again.') . '</p>', 410);
	}
	// A client that was linked to an account before may only log in to that account again
	if (!empty($info['userID']) && (int) $info['userID'] !== (int) $user['userID']) {
		page(t('Different account'), '<p>' . t('This Zotero is linked to a different account. Log in with that account or unlink the account in Zotero.') . '</p>', 403);
	}

	if ($_SERVER['REQUEST_METHOD'] === 'POST') {
		if (!hash_equals($_SESSION['csrf'][$token] ?? '', $_POST['csrf'] ?? '')) {
			page(t('Request rejected'), '<p>' . t('The confirmation was invalid. Open the link from Zotero again.') . '</p>', 403);
		}
		unset($_SESSION['csrf'][$token]);
		if (($_POST['action'] ?? '') !== 'allow') {
			Api::request('DELETE', "keys/sessions/$token");
			page(t('Cancelled'), '<p>' . t('Zotero was not connected. You can close this window.') . '</p>');
		}
		[$status] = Api::request('POST', 'keys/sessions/complete', [
			'sessionToken' => $token,
			'userID' => (int) $user['userID'],
			'access' => Accounts::FULL_ACCESS
		], true);
		if ($status != 204) {
			error_log("Completing login session failed: $status");
			page(t('Error'), '<p>' . t('Zotero could not be connected. Start the login in Zotero again.') . '</p>', 500);
		}
		page(t('Zotero is connected'), '<p>' . t('Zotero now syncs with the account %s. You can close this window and return to Zotero.', "<b>$name</b>") . '</p>');
	}

	// Explicit confirmation, so a login link sent by someone else can't take over the account
	$_SESSION['csrf'][$token] = bin2hex(random_bytes(16));
	$csrf = $_SESSION['csrf'][$token];
	$client = htmlspecialchars($info['clientType'] ?? 'Zotero');
	page(t('Connect Zotero'), '<p>' . t('Should %s on your device get access to your Zotero library (account %s)?', "<b>$client</b>", "<b>$name</b>") . '</p>'
		. '<p>' . t('Only confirm if you just started the login in Zotero yourself.') . '</p>'
		. '<form method="post"><input type="hidden" name="session" value="' . htmlspecialchars($token) . '">'
		. '<input type="hidden" name="csrf" value="' . $csrf . '">'
		. '<button name="action" value="allow">' . t('Connect') . '</button><button name="action" value="deny">' . t('Cancel') . '</button></form>');
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
	'translateUrl' => "$baseURL/translate",
	'libraries' => ['includeMyLibrary' => true, 'includeUserGroups' => true]
];
$menu = [
	'desktop' => [
		['label' => 'My Library', 'href' => '/', 'active' => true],
		['label' => $user['username'], 'dropdown' => true, 'truncate' => true, 'entries' => [['label' => t('Log out'), 'href' => '/logout']]]
	],
	'mobile' => [
		['label' => 'My Library', 'href' => '/', 'active' => true],
		['label' => t('Log out'), 'href' => '/logout']
	]
];
$json = fn($v) => json_encode($v, JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP);
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
echo str_replace(['{{CONFIG}}', '{{MENU}}'], [$json($config), $json($menu)], file_get_contents(__DIR__ . '/web-library.html'));
