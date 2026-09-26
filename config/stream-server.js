// Overrides for the upstream config/default.js, copied to config/local.js in the image
module.exports = {
	redis: {
		url: 'redis://redis:6379',
		prefix: ''
	},
	// Internal URL of the dataserver, used to verify API keys
	apiURL: 'http://dataserver/'
};
