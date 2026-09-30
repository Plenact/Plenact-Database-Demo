<?php
declare(strict_types=1);

ini_set('display_errors', '0');

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_THROW_ON_ERROR);
    exit;
}

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        header('Allow: GET');
        respond(405, ['error' => 'method_not_allowed']);
    }

    $path = dirname(__DIR__, 3) . '/plenact-private/api-auth.json';
    $json = @file_get_contents($path);

    if ($json === false) {
        throw new RuntimeException('Configuration unavailable');
    }

    $auth = json_decode($json, true, 512, JSON_THROW_ON_ERROR);

    foreach (['app_token', 'reader_token'] as $key) {
        if (!isset($auth[$key])
            || !is_string($auth[$key])
            || preg_match('/\A[A-Za-z0-9]{64}\z/', $auth[$key]) !== 1) {
            throw new RuntimeException('Invalid token configuration');
        }
    }

    if (hash_equals($auth['app_token'], $auth['reader_token'])) {
        throw new RuntimeException('Tokens must differ');
    }

    $authorization = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? '';

    if (preg_match(
        '/\ABearer ([A-Za-z0-9]{64})\z/i',
        $authorization,
        $matches
    ) !== 1) {
        header('WWW-Authenticate: Bearer realm="plenact-dev"');
        respond(401, ['error' => 'unauthorized']);
    }

    $isApp = hash_equals($auth['app_token'], $matches[1]);
    $isReader = hash_equals($auth['reader_token'], $matches[1]);

    if (!$isApp && !$isReader) {
        header('WWW-Authenticate: Bearer realm="plenact-dev"');
        respond(401, ['error' => 'unauthorized']);
    }

    if (!$isApp) {
        respond(403, ['error' => 'forbidden']);
    }

// ORIGINAL
//
//    respond(200, ['authenticated' => true, 'role' => 'app']);
//
// NEW
//
    $databasePath = dirname(__DIR__, 3)
        . '/plenact-private/database.json';

    $databaseJson = @file_get_contents($databasePath);
    if ($databaseJson === false) {
        throw new RuntimeException('Database configuration unavailable');
    }

    $database = json_decode(
        $databaseJson,
        true,
        512,
        JSON_THROW_ON_ERROR
    );

    foreach (['host', 'database', 'username', 'password'] as $key) {
        if (!isset($database[$key])
            || !is_string($database[$key])
            || $database[$key] === '') {
            throw new RuntimeException('Invalid database configuration');
        }
    }

    $pdo = new PDO(
        "mysql:host={$database['host']};"
        . "dbname={$database['database']};charset=utf8mb4",
        $database['username'],
        $database['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_TIMEOUT => 5
        ]
    );

    $statement = $pdo->prepare(
        'SELECT config_value, version
         FROM app_config
         WHERE config_key = :config_key'
    );
    $statement->execute(['config_key' => 'welcome_message']);
    $configuration = $statement->fetch();

    if ($configuration === false) {
        throw new RuntimeException('Required configuration missing');
    }

    $statement = $pdo->prepare(
        'SELECT notice_id, message
         FROM notices
         WHERE is_active = :active
         ORDER BY notice_id DESC
         LIMIT 1'
    );
    $statement->execute(['active' => 1]);
    $notice = $statement->fetch();

    respond(200, [
        'configuration' => [
            'welcome_message' => $configuration['config_value'],
            'version' => (int) $configuration['version']
        ],
        'notice' => $notice === false ? null : [
            'id' => (int) $notice['notice_id'],
            'message' => $notice['message']
        ]
    ]);
//
// END

} catch (Throwable $error) {
    
// ORIGINAL
//
//    respond(500, ['error' => 'server_configuration_error']);
//
// NEW
//
    respond(500, ['error' => 'server_error']);
//
// END
}