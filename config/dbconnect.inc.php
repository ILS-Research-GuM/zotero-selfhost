<?
function Zotero_dbConnectAuth($db) {
	$databases = [
		'master' => 'zotero_master',
		'shard' => 'zotero_shard_1',
		'id1' => 'zotero_ids',
		'id2' => 'zotero_ids',
		'www1' => 'zotero_www',
		'www2' => 'zotero_www'
	];
	if (!isset($databases[$db])) {
		throw new Exception("Invalid db '$db'");
	}
	return [
		'host' => getenv('MYSQL_HOST') ?: 'mysql',
		'replicas' => [],
		'port' => 3306,
		'db' => $databases[$db],
		'user' => 'root',
		'pass' => getenv('MYSQL_ROOT_PASSWORD'),
		'charset' => '',
		'state' => 'up'
	];
}
?>
