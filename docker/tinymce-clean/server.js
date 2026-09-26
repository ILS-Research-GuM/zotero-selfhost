// Drop-in replacement for the Koa 1 server of zotero/tinymce-clean-server,
// reusing its unchanged cleaning logic from lib/utils.js
'use strict';

const http = require('http');
const utils = require('./lib/utils');

const TEXT_LIMIT = 250000;
const host = process.env.TINYMCE_CLEAN_HOST || undefined;
const port = process.env.TINYMCE_CLEAN_PORT || 16342;

const server = http.createServer((req, res) => {
	if (req.method !== 'POST' || req.headers['content-type'] !== 'text/plain') {
		res.writeHead(400).end();
		return;
	}
	let chunks = [];
	let size = 0;
	req.on('data', (chunk) => {
		size += chunk.length;
		if (size > TEXT_LIMIT) {
			res.writeHead(413).end();
			req.destroy();
			return;
		}
		chunks.push(chunk);
	});
	req.on('end', () => {
		if (res.writableEnded) {
			return;
		}
		let start = Date.now();
		let input = Buffer.concat(chunks).toString('utf8');
		let output;
		try {
			output = utils.process(input);
		}
		catch (e) {
			console.error(e);
			res.writeHead(500).end();
			return;
		}
		console.log(`Note ${output != input ? 'cleaned' : 'unchanged'} in ${Date.now() - start} ms`);
		res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' }).end(output);
	});
});

server.listen(port, host, () => console.log(`Listening on port ${port}`));
