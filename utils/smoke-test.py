#!/usr/bin/env python3
"""End-to-end check of a running stack, doing what the desktop client does.

Usage: sudo utils/smoke-test.py [--public]   (after docker compose up -d and bin/init.sh)

By default talks to the services via 127.0.0.1 and the ports from .env, so it also
works when BIND_ADDRESS is 127.0.0.1. With --public it uses the client-facing URLs
from .env instead, which also tests the reverse proxy. Environment variables override
values from .env, e.g. PORTAL_PORT, OIDC_ISSUER and PASSWORD_LOGIN to check a second portal
started with other login settings.
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def load_env():
	env = {}
	with open(os.path.join(ROOT, '.env')) as f:
		for line in f:
			line = line.strip()
			if line and not line.startswith('#') and '=' in line:
				k, v = line.split('=', 1)
				env[k] = v
	return env


ENV = load_env()
ENV.update({k: v for k, v in os.environ.items() if k in ENV or k in ('PORTAL_PORT', 'PASSWORD_LOGIN')})
PUBLIC = '--public' in sys.argv
API = ENV['ZOTERO_API_URL'].rstrip('/') if PUBLIC else f"http://127.0.0.1:{ENV['API_PORT']}"
STREAM = ENV['STREAMING_URL'] if PUBLIC else 'ws://localhost:8080'
S3_LOCAL = None if PUBLIC else f"127.0.0.1:{ENV['S3_PORT']}"
WEB = ENV['WEB_LIBRARY_URL'] if PUBLIC else f"http://127.0.0.1:{ENV['WEB_LIBRARY_PORT']}"
PORTAL = ENV['WEB_LIBRARY_URL'].rstrip('/') if PUBLIC else f"http://127.0.0.1:{ENV.get('PORTAL_PORT', '8184')}"
failures = 0


def check(name, ok, detail=''):
	global failures
	print(f"{'OK  ' if ok else 'FAIL'} {name}" + (f" -- {detail}" if detail and not ok else ''))
	if not ok:
		failures += 1
	return ok


def request(method, url, body=None, headers=None, host=None):
	headers = dict(headers or {})
	parsed = urllib.parse.urlsplit(url)
	# Connect locally but keep the public Host header, which S3 signatures cover
	if host:
		headers['Host'] = parsed.netloc
		url = urllib.parse.urlunsplit(('http', host, parsed.path, parsed.query, ''))
	if isinstance(body, str):
		body = body.encode()
	req = urllib.request.Request(url, data=body, method=method, headers=headers)

	class NoRedirect(urllib.request.HTTPRedirectHandler):
		def redirect_request(self, *args, **kwargs):
			return None

	try:
		r = urllib.request.build_opener(NoRedirect).open(req, timeout=30)
		return r.status, r.headers, r.read()
	except urllib.error.HTTPError as e:
		return e.code, e.headers, e.read()


def api(method, path, data=None, key=None, headers=None):
	h = {'Zotero-API-Version': '3'}
	if key:
		h['Zotero-API-Key'] = key
	if isinstance(data, (dict, list)):
		data = json.dumps(data)
		h['Content-Type'] = 'application/json'
	h.update(headers or {})
	status, hdrs, body = request(method, API + path, data, h)
	try:
		return status, hdrs, json.loads(body) if body else None
	except ValueError:
		return status, hdrs, body.decode(errors='replace')


def main():
	status, _, _ = api('GET', '/schema')
	check('API reachable, schema served', status == 200, status)

	status, _, _ = api('POST', '/keys', {'username': ENV['ZOTERO_ADMIN_USER'], 'password': 'wrong', 'name': 'x'})
	check('Login with wrong password rejected', status == 403, status)

	status, _, key = api('POST', '/keys', {
		'username': ENV['ZOTERO_ADMIN_USER'], 'password': ENV['ZOTERO_ADMIN_PASSWORD'], 'name': 'smoke-test',
		'access': {'user': {'library': True, 'files': True, 'notes': True, 'write': True},
			'groups': {'all': {'library': True, 'write': True}}}})
	if not check('Login creates API key', status == 201, f"{status} {key}"):
		return
	userID, key = key['userID'], key['key']

	try:
		run_tests(userID, key)
	finally:
		api('DELETE', '/keys/current', key=key)
	portal_tests()


def portal_tests():
	"""The portal: login redirects to the OIDC provider, and with password login a real login"""
	status, _, _ = request('POST', PORTAL + '/translate/search', b'10.1038/nature12373',
		{'Content-Type': 'text/plain', 'Sec-Fetch-Mode': 'cors'})
	check('Portal: translation server needs a login', status == 401, status)
	oidc = bool(ENV.get('OIDC_ISSUER'))
	pw = ENV.get('PASSWORD_LOGIN', '').lower() in ('1', 'true', 'yes', 'on') if ENV.get('PASSWORD_LOGIN') else not oidc
	if pw:
		portal_password_tests(oidc)
	if not oidc:
		return
	try:
		with urllib.request.urlopen(ENV['OIDC_ISSUER'].rstrip('/') + '/.well-known/openid-configuration', timeout=30) as r:
			authEndpoint = json.load(r)['authorization_endpoint']
	except Exception as e:
		check('OIDC provider discovery', False, e)
		return

	def login_redirect(path):
		status, headers, _ = request('GET', PORTAL + path, headers={'Sec-Fetch-Mode': 'navigate'})
		location = headers.get('Location', '')
		query = urllib.parse.parse_qs(urllib.parse.urlsplit(location).query)
		ok = (status == 302 and location.startswith(authEndpoint + '?')
			and query.get('client_id') == [ENV.get('OIDC_CLIENT_ID')]
			and query.get('redirect_uri') == [ENV['WEB_LIBRARY_URL'].rstrip('/') + '/oidc/callback']
			and 'state' in query and 'nonce' in query)
		return ok, f"{status} {location[:120]}"

	if pw:
		check('Portal: OIDC button on the sign-in page leads to the OIDC login', *login_redirect('/oidc/start'))
	else:
		check('Portal: web-library page redirects to the OIDC login', *login_redirect('/'))
		check('Portal: desktop client login requires the OIDC login', *login_redirect('/login?session=smoketest'))
	status, _, _ = request('GET', PORTAL + '/oidc/callback?state=bogus&code=bogus')
	check('Portal: callback with unknown state rejected', status == 400, status)
	status, _, _ = request('GET', PORTAL + '/', headers={'Sec-Fetch-Mode': 'cors'})
	check('Portal: background requests get 401 instead of a login redirect', status == 401, status)
	# Downloads are public (Zotero checks plugin updates without a session); the directory may be empty
	status, _, _ = request('GET', PORTAL + '/downloads')
	check('Portal: downloads page reachable without login', status == 200, status)
	# 404 from the portal, or a login redirect if a reverse proxy normalized the path first
	status, _, _ = request('GET', PORTAL + '/downloads/../.env')
	check('Portal: downloads refuse paths outside the directory', status in (302, 404), status)
	status, _, _ = request('GET', PORTAL + '/downloads/%2e%2e/%2eenv')
	check('Portal: downloads refuse encoded paths outside the directory', status in (302, 404), status)


def portal_password_tests(oidc):
	"""Password login: sign-in page, wrong password rejected, login as the admin user"""
	# Cookies by hand: the session cookie is secure when WEB_LIBRARY_URL is https, even if the
	# portal is reached over plain HTTP locally
	cookie = {}

	def get(path, body=None, headers=None):
		h = {'Sec-Fetch-Mode': 'navigate', **(headers or {})}
		if cookie:
			h['Cookie'] = '; '.join(f"{k}={v}" for k, v in cookie.items())
		if isinstance(body, dict):
			body = urllib.parse.urlencode(body)
			h.setdefault('Content-Type', 'application/x-www-form-urlencoded')
		status, headers, data = request('POST' if body is not None else 'GET', PORTAL + path, body, h)
		for c in headers.get_all('Set-Cookie') or []:
			k, v = c.split(';', 1)[0].split('=', 1)
			cookie[k] = v
		return status, headers, data.decode(errors='replace')

	base = ENV['WEB_LIBRARY_URL'].rstrip('/')
	status, headers, _ = get('/login?session=smoketest')
	check('Portal: login required, redirects to the password form',
		status == 302 and headers.get('Location') == base + '/signin', f"{status} {headers.get('Location')}")
	status, _, page = get('/signin')
	csrf = page.split('name="csrf" value="', 1)[-1].split('"', 1)[0]
	check('Portal: password form served', status == 200 and 'type="password"' in page and len(csrf) == 32
		and ('action="/oidc/start"' in page) == oidc, status)
	status, _, _ = get('/signin', {'csrf': csrf, 'username': ENV['ZOTERO_ADMIN_USER'], 'password': 'wrong'})
	check('Portal: wrong password rejected', status == 401, status)
	status, _, _ = get('/signin', {'csrf': 'bogus', 'username': ENV['ZOTERO_ADMIN_USER'], 'password': ENV['ZOTERO_ADMIN_PASSWORD']})
	check('Portal: form without valid CSRF token rejected', status == 403, status)
	status, headers, _ = get('/signin', {'csrf': csrf, 'username': ENV['ZOTERO_ADMIN_USER'], 'password': ENV['ZOTERO_ADMIN_PASSWORD']})
	check('Portal: password login returns to the desktop client login',
		status == 302 and headers.get('Location') == base + '/login?session=smoketest', f"{status} {headers.get('Location')}")
	status, _, page = get('/')
	check('Portal: web-library page with user configuration', status == 200 and '"apiKey"' in page
		and '"translateUrl"' in page, status)
	# Needs internet access from the translation server (doi.org, Crossref)
	status, _, body = get('/translate/search', '10.1038/nature12373', {'Content-Type': 'text/plain', 'Sec-Fetch-Mode': 'cors'})
	check('Portal: translation server resolves a DOI', status == 200 and 'Nanometre-scale thermometry' in body,
		f"{status} {body[:200]}")

def run_tests(userID, key):
	lib = f'/users/{userID}'

	status, _, groups = api('GET', f'{lib}/groups', key=key)
	# Without SHARED_GROUP_OWNER there is no shared group, so an empty list is fine then
	check('Group libraries listed', status == 200 and (len(groups) > 0 or not ENV.get('SHARED_GROUP_OWNER')),
		f"{status} {groups}")

	status, _, res = api('POST', f'{lib}/items', [
		{'itemType': 'book', 'title': 'Smoke test book', 'creators': [{'creatorType': 'author', 'firstName': 'Ada', 'lastName': 'Lovelace'}]},
		{'itemType': 'note', 'note': '<div>Hallo<script>evil()</script> <b>Welt</b></div>'},
		{'itemType': 'attachment', 'linkMode': 'imported_file', 'title': 'smoke.pdf', 'contentType': 'application/pdf', 'filename': 'smoke.pdf'},
	], key=key)
	if not check('Items created (book, note, attachment)', status == 200 and not res['failed'], f"{status} {res}"):
		return
	bookKey, noteKey, attKey = (res['successful'][str(i)]['key'] for i in range(3))

	status, _, note = api('GET', f'{lib}/items/{noteKey}', key=key)
	html = note['data']['note'] if status == 200 else ''
	check('Note HTML cleaned by tinymce-clean', 'script' not in html and '<strong>Welt</strong>' in html, html)

	if groups:
		g = groups[0]['data']
		canWrite = (g['libraryEditing'] == 'members' or g.get('owner') == userID
			or userID in g.get('admins', []))
		status, _, res = api('POST', f"/groups/{g['id']}/items", [{'itemType': 'journalArticle', 'title': 'Smoke test'}], key=key)
		if canWrite:
			check('Item created in group library', status == 200 and not res['failed'], f"{status} {res}")
			if status == 200 and res['successful']:
				gKey = list(res['successful'].values())[0]['key']
				api('DELETE', f"/groups/{g['id']}/items/{gKey}", key=key,
					headers={'If-Unmodified-Since-Version': str(list(res['successful'].values())[0]['version'])})
		else:
			check('Read-only group rejects writes from members', status == 403, f"{status} {res}")

	# File upload as the client does it: request, POST to S3, register, download
	content = f'%PDF-1.4 smoke test {time.time()}\n'.encode()
	md5 = hashlib.md5(content).hexdigest()
	status, _, upload = api('POST', f'{lib}/items/{attKey}/file',
		f'md5={md5}&filename=smoke.pdf&filesize={len(content)}&mtime={int(time.time() * 1000)}',
		key=key, headers={'If-None-Match': '*', 'Content-Type': 'application/x-www-form-urlencoded'})
	if not check('File upload authorized', status == 200 and 'uploadKey' in upload, f"{status} {upload}"):
		return
	check('Upload URL uses S3_PUBLIC_URL', upload['url'].startswith(ENV['S3_PUBLIC_URL']), upload['url'])
	status, _, body = request('POST', upload['url'], upload['prefix'].encode() + content + upload['suffix'].encode(),
		{'Content-Type': upload['contentType']}, host=S3_LOCAL)
	check('File stored in S3 (signed POST)', status == 201, f"{status} {body[:300]}")
	status, _, body = api('POST', f'{lib}/items/{attKey}/file', f"upload={upload['uploadKey']}",
		key=key, headers={'If-None-Match': '*', 'Content-Type': 'application/x-www-form-urlencoded'})
	check('Upload registered', status == 204, f"{status} {body}")
	status, hdrs, _ = api('GET', f'{lib}/items/{attKey}/file', key=key)
	location = hdrs.get('Location', '')
	if check('Download redirects to presigned URL', status == 302 and location.startswith(ENV['S3_PUBLIC_URL']), f"{status} {location}"):
		status, _, body = request('GET', location, host=S3_LOCAL)
		check('Downloaded file matches upload', status == 200 and body == content, status)
	# The web-library opens attachments via the view URL
	status, _, body = api('GET', f'{lib}/items/{attKey}/file/view/url', key=key)
	viewURL = (body.decode() if isinstance(body, bytes) else str(body)).strip()
	check('View URL is a presigned S3 URL', status == 200 and viewURL.startswith(ENV['S3_PUBLIC_URL']), f"{status} {viewURL[:80]}")

	status, _, _ = api('PUT', f'{lib}/items/{attKey}/fulltext', {'content': 'smoke test full text', 'indexedPages': 1, 'totalPages': 1}, key=key)
	check('Full text stored', status == 204, status)
	status, _, ft = api('GET', f'{lib}/items/{attKey}/fulltext', key=key)
	check('Full text read back', status == 200 and ft.get('content') == 'smoke test full text', f"{status} {ft}")

	# Streaming: subscribe with the key, change the library, expect a topicUpdated push
	script = r'''
const ws = new WebSocket(process.argv[2]);
const out = (o) => { console.log(JSON.stringify(o)); };
setTimeout(() => { out({event: "timeout"}); process.exit(1); }, 20000);
ws.onmessage = (m) => {
	const d = JSON.parse(m.data);
	out(d);
	if (d.event === "connected") ws.send(JSON.stringify({action: "createSubscriptions", subscriptions: [{apiKey: process.argv[1]}]}));
	if (d.event === "topicUpdated") process.exit(0);
};
'''
	proc = subprocess.Popen(['docker', 'compose', 'exec', '-T', 'stream-server', 'node', '-e', script, key, STREAM],
		cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
	events = []
	for line in proc.stdout:
		try:
			events.append(json.loads(line))
		except ValueError:
			continue
		if events[-1].get('event') == 'subscriptionsCreated':
			api('POST', f'{lib}/items', [{'itemType': 'book', 'title': 'Streaming trigger'}], key=key)
	proc.wait()
	names = [e.get('event') for e in events]
	subs = next((e for e in events if e.get('event') == 'subscriptionsCreated'), {})
	check('Stream: subscription created', bool(subs.get('subscriptions')) and not subs.get('errors'), subs)
	check('Stream: topicUpdated pushed after change', 'topicUpdated' in names, names)

	status, _, _ = api('DELETE', f'{lib}/items?itemKey={bookKey},{noteKey},{attKey}', key=key,
		headers={'If-Unmodified-Since-Version': str(api('GET', f'{lib}/items?limit=1', key=key)[1]['Last-Modified-Version'])})
	check('Items deleted', status == 204, status)

	# The page itself needs an OIDC login (portal); check the static assets
	status, headers, _ = request('GET', WEB + '/static/web-library/zotero-web-library.js')
	check('web-library assets served', status == 200, status)
	status, headers, _ = request('GET', WEB + '/static/web-library/reader/pdf/build/pdf.mjs')
	check('PDF viewer modules served as JavaScript',
		status == 200 and 'javascript' in headers.get('Content-Type', ''), f"{status} {headers.get('Content-Type')}")


main()
print('All checks passed' if not failures else f'{failures} check(s) failed')
sys.exit(1 if failures else 0)
