<?php
/**************************************************************************************************
 * @file       auth-check.php
 * @brief      Verify app-role authentication for the development API
 * @details    Validate a bearer token and report whether it has app access
 *
 * @author     Justin Reina
 * @created    10/01/26
 * @last rev   10/01/26
 *
 * @notes      Database credentials are not read by this endpoint.
 *
 **************************************************************************************************/
declare(strict_types=1);


// -------------------------------------- MARK: - Runtime Settings ------------------------------ //

ini_set('display_errors', '0');

const JSON_DECODE_DEPTH = 512;
const API_TOKEN_PATTERN = '/\A[A-Za-z0-9]{64}\z/';
const BEARER_TOKEN_PATTERN = '/\ABearer ([A-Za-z0-9]{64})\z/i';
const PRIVATE_DIRECTORY_LEVELS = 3;


// -------------------------------------- MARK: - Response Helper ------------------------------- //

/**
 * @fcn        respond
 * @brief      Send a JSON response and stop request processing.
 * @details    Centralize response status, headers, encoding, and termination.
 *
 * @param[in]  $status  HTTP status code.
 * @param[in]  $body    JSON-serializable response fields.
 *
 * @return     (never) execution terminates after the response is written.
 * @throws     JsonException if response encoding fails.
 *
 * @pre        $body can be encoded as JSON.
 * @post       Response headers and body are sent; execution terminates.
 *
 * @note       Do not include token values or internal configuration in responses.
 */
function respond(int $status, array $body): never
{
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');

  echo json_encode($body, JSON_THROW_ON_ERROR);
  exit;
}


// -------------------------------------- MARK: - Authentication ------------------------------- //

try {
  if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
    header('Allow: GET');
    respond(405, ['error' => 'method_not_allowed']);
  }

  $authPath = dirname(__DIR__, PRIVATE_DIRECTORY_LEVELS)
    . '/plenact-private/api-auth.json';
  $authJson = @file_get_contents($authPath);

  if ($authJson === false) {
    throw new RuntimeException('Configuration unavailable');
  }

  $auth = json_decode($authJson, true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR);

  foreach (['app_token', 'reader_token'] as $key) {
    if (!isset($auth[$key])
        || !is_string($auth[$key])
        || preg_match(API_TOKEN_PATTERN, $auth[$key]) !== 1) {
      throw new RuntimeException('Invalid token configuration');
    }
  }

  if (hash_equals($auth['app_token'], $auth['reader_token'])) {
    throw new RuntimeException('Tokens must differ');
  }

  $authorization = $_SERVER['HTTP_AUTHORIZATION']
    ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
    ?? '';

  if (preg_match(BEARER_TOKEN_PATTERN, $authorization, $matches) !== 1) {
    header('WWW-Authenticate: Bearer realm="plenact-dev"');
    respond(401, ['error' => 'unauthorized']);
  }

  $is_app = hash_equals($auth['app_token'], $matches[1]);
  $is_reader = hash_equals($auth['reader_token'], $matches[1]);

  if (!$is_app && !$is_reader) {
    header('WWW-Authenticate: Bearer realm="plenact-dev"');
    respond(401, ['error' => 'unauthorized']);
  }

  if (!$is_app) {
    respond(403, ['error' => 'forbidden']);
  }

  respond(200, ['authenticated' => true, 'role' => 'app']);
} catch (Throwable) {
  respond(500, ['error' => 'server_configuration_error']);
}