import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
export default {
	kit: {
		adapter: adapter(),
		// Forms carry their own CSRF tokens (see lib/server/session.ts). Kit's origin check would
		// reject clients without an Origin header and needs the public origin behind the proxy.
		csrf: { trustedOrigins: ['*'] },
		// Pages render without client-side JavaScript; inline the CSS so the strict CSP holds
		inlineStyleThreshold: Infinity
	}
};
