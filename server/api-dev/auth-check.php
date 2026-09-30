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

    respond(200, ['authenticated' => true, 'role' => 'app']);
} catch (Throwable $error) {
    respond(500, ['error' => 'server_configuration_error']);
}