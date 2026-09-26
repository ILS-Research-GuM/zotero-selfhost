<?
function zenv($name, $default = '') {
	$value = getenv($name);
	return $value === false ? $default : $value;
}

class Z_CONFIG {
	public static $API_ENABLED = true;
	public static $READ_ONLY = false;
	public static $MAINTENANCE_MESSAGE = 'Server updates in progress. Please try again in a few minutes.';
	public static $BACKOFF = 0;

	public static $TESTING_SITE = false;
	public static $DEV_SITE = false;

	public static $DEBUG_LOG = false;

	// Object URI namespace, not a real URL -- must match ZOTERO_CONFIG.BASE_URI in the client
	public static $BASE_URI = 'http://zotero.org/';
	public static $API_BASE_URI;
	public static $WWW_BASE_URI;

	public static $AUTH_SALT;
	public static $API_SUPER_USERNAME;
	public static $API_SUPER_PASSWORD;

	public static $AWS_REGION = 'us-east-1';
	public static $AWS_ACCESS_KEY;
	public static $AWS_SECRET_KEY;
	// Internal S3 endpoint used by the dataserver itself
	public static $S3_ENDPOINT;
	// S3 endpoint as reachable by clients, used for upload and download URLs
	public static $S3_PUBLIC_URL;
	public static $S3_BUCKET = 'zotero';
	public static $S3_BUCKET_CACHE = '';
	public static $S3_BUCKET_FULLTEXT = 'zotero-fulltext';
	// Empty: don't track full-text index state in DynamoDB
	public static $FULLTEXT_INDEXING_TABLE = '';
	public static $S3_BUCKET_ERRORS = '';
	public static $SNS_ALERT_TOPIC = '';

	public static $REDIS_HOSTS = [
		'default' => ['host' => 'redis:6379'],
		'request-limiter' => ['host' => 'redis:6379'],
		'notifications' => ['host' => 'redis:6379'],
		'fulltext-migration' => ['host' => 'redis:6379', 'cluster' => false]
	];

	public static $REDIS_PREFIX = '';

	public static $MEMCACHED_ENABLED = true;
	public static $MEMCACHED_SERVERS = ['memcached:11211:1'];

	public static $TRANSLATION_SERVERS = [];

	public static $CITATION_SERVERS = [];

	// Empty: no server-side full-text search (clients search their local index)
	public static $SEARCH_HOSTS = [];

	public static $GLOBAL_ITEMS_URL = '';

	public static $ATTACHMENT_PROXY_URL = '';
	public static $ATTACHMENT_PROXY_SECRET = '';

	public static $TTS_TABLE = '';
	public static $S3_BUCKET_TTS = '';
	public static $TTS_AUDIO_DOMAIN = '';
	public static $TTS_CREDIT_LIMITS = [];
	public static $TTS_DAILY_LIMIT_MINUTES = 0;

	public static $STATSD_ENABLED = false;
	public static $STATSD_PREFIX = "";
	public static $STATSD_HOST = "";
	public static $STATSD_PORT = 8125;

	public static $LOG_TO_SCRIBE = false;
	public static $LOG_ADDRESS = '';
	public static $LOG_PORT = 1463;
	public static $LOG_TIMEZONE = 'Europe/Berlin';
	public static $LOG_TARGET_DEFAULT = 'errors';

	public static $HTMLCLEAN_SERVER_URL = 'http://tinymce-clean:16342';

	public static $CLI_PHP_PATH = '/usr/local/bin/php';

	public static $ERROR_PATH = '/var/www/zotero/errors/';

	public static $CACHE_VERSION_ATOM_ENTRY = 1;
	public static $CACHE_VERSION_BIB = 1;
	public static $CACHE_VERSION_RESPONSE_JSON_COLLECTION = 1;
	public static $CACHE_VERSION_RESPONSE_JSON_ITEM = 1;
	public static $CACHE_ENABLED_ITEM_RESPONSE_JSON = true;

	public static $REINDEX_QUEUE_URL = '';

	public static function init() {
		self::$API_BASE_URI = rtrim(zenv('ZOTERO_API_URL', 'http://localhost:8080'), '/') . '/';
		self::$WWW_BASE_URI = rtrim(zenv('ZOTERO_WWW_URL', self::$API_BASE_URI), '/') . '/';
		self::$AUTH_SALT = zenv('ZOTERO_AUTH_SALT');
		self::$API_SUPER_USERNAME = zenv('ZOTERO_SUPER_USER', 'admin');
		self::$API_SUPER_PASSWORD = zenv('ZOTERO_SUPER_PASSWORD');
		self::$AWS_ACCESS_KEY = zenv('S3_ACCESS_KEY');
		self::$AWS_SECRET_KEY = zenv('S3_SECRET_KEY');
		self::$S3_ENDPOINT = zenv('S3_ENDPOINT', 'http://minio:9000');
		self::$S3_PUBLIC_URL = zenv('S3_PUBLIC_URL', 'http://localhost:8082');
	}
}
Z_CONFIG::init();
?>
