<?php
/**************************************************************************************************
 * @file       preferences.php
 * @brief      Save the latest preferences for the configured app installation
 * @details    Accept an app-authenticated JSON request and upsert it into MySQL
 *
 * @author     Justin Reina
 * @created    10/01/26
 * @last rev   10/01/26
 *
 * @notes      Apply 002_installation_preferences.sql and deploy this endpoint before hosted use.
 *             Private authentication and database configuration stay outside the web root.
 *
 * @section    Opens
 *      Add a separate reader endpoint only after its access policy is designed
 *
 **************************************************************************************************/
declare(strict_types=1);


// -------------------------------------- MARK: - Runtime Settings ------------------------------ //

ini_set('display_errors', '0');

const JSON_DECODE_DEPTH            = 512; /* JSON nesting limit                               */
const API_TOKEN_PATTERN            = '/\A[A-Za-z0-9]{64}\z/'; /* 64-character token pattern                     */
const BEARER_TOKEN_PATTERN         = '/\ABearer ([A-Za-z0-9]{64})\z/i'; /* Bearer header pattern                  */
const MAX_REQUEST_BODY_BYTES       = 8192; /* Maximum request body size             */
const MAX_FAVORITE_FOOD_CODEPOINTS = 255; /* Maximum food-name code points       */
const MIN_CAT_COUNT                = 1; /* Minimum cat count                                     */
const MAX_CAT_COUNT                = 4_294_967_295; /* Maximum cat count                                     */
const PRIVATE_DIRECTORY_LEVELS     = 3; /* Private configuration path depth */
const DATABASE_TIMEOUT_SECONDS     = 5; /* Database timeout seconds                        */


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
 * @note       Never include credentials, paths, or internal exception details in the response.
 */
function respond(int $status, array $body): never
{
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');

  echo json_encode($body, JSON_THROW_ON_ERROR);
  exit;
}


// -------------------------------------- MARK: - Request Validation ---------------------------- //

try {
  if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    respond(405, ['error' => 'method_not_allowed']);
  }

  // Resolve private configuration from the endpoint's deployed directory.
  $privateDirectory = dirname(__DIR__, PRIVATE_DIRECTORY_LEVELS);
  $authPath = $privateDirectory . '/plenact-private/api-auth.json';
  $authJson = @file_get_contents($authPath);

  if ($authJson === false) {
    throw new RuntimeException('Authentication configuration unavailable');
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

  if (!isset($auth['installation_id'])
      || !is_string($auth['installation_id'])
      || preg_match(
        '/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/',
        $auth['installation_id']
      ) !== 1) {
    throw new RuntimeException('Invalid installation identifier');
  }

  $authorization = $_SERVER['HTTP_AUTHORIZATION']
    ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
    ?? '';

  if (preg_match(BEARER_TOKEN_PATTERN, $authorization, $matches) !== 1) {
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

  $contentType = strtolower(trim(explode(
    ';',
    $_SERVER['CONTENT_TYPE'] ?? ''
  )[0]));

  if ($contentType !== 'application/json') {
    respond(415, ['error' => 'unsupported_media_type']);
  }

  // Read and validate the bounded JSON request body before opening a database connection.
  $rawBody = file_get_contents('php://input');

  if ($rawBody === false || $rawBody === '') {
    respond(400, ['error' => 'invalid_json']);
  }

  if (strlen($rawBody) > MAX_REQUEST_BODY_BYTES) {
    respond(413, ['error' => 'request_too_large']);
  }

  try {
    $payload = json_decode($rawBody, true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR);
  } catch (JsonException) {
    respond(400, ['error' => 'invalid_json']);
  }

  if (!is_array($payload)
      || !isset($payload['favorite_food'])
      || !is_string($payload['favorite_food'])
      || !isset($payload['cat_count'])
      || !is_int($payload['cat_count'])) {
    respond(422, ['error' => 'invalid_payload']);
  }

  $favoriteFood = trim($payload['favorite_food']);
  $favoriteFoodPattern = sprintf(
    '/\A[^\x00-\x1F\x7F]{1,%d}\z/u',
    MAX_FAVORITE_FOOD_CODEPOINTS
  );

  if (preg_match($favoriteFoodPattern, $favoriteFood) !== 1) {
    respond(422, ['error' => 'invalid_favorite_food']);
  }

  if ($payload['cat_count'] < MIN_CAT_COUNT || $payload['cat_count'] > MAX_CAT_COUNT) {
    respond(422, ['error' => 'invalid_cat_count']);
  }


  // -------------------------------------- MARK: - Database Access ----------------------------- //

  $databasePath = $privateDirectory . '/plenact-private/database.json';
  $databaseJson = @file_get_contents($databasePath);

  if ($databaseJson === false) {
    throw new RuntimeException('Database configuration unavailable');
  }

  $database = json_decode($databaseJson, true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR);

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
      PDO::ATTR_TIMEOUT => DATABASE_TIMEOUT_SECONDS,
    ]
  );

  $statement = $pdo->prepare(
    'INSERT INTO installation_preferences (
      installation_id,
      favorite_food,
      cat_count,
      updated_at
    ) VALUES (
      :installation_id,
      :favorite_food,
      :cat_count,
      UTC_TIMESTAMP(6)
    )
    ON DUPLICATE KEY UPDATE
      favorite_food = :updated_favorite_food,
      cat_count = :updated_cat_count,
      updated_at = UTC_TIMESTAMP(6)'
  );
  $statement->execute([
    'installation_id' => $auth['installation_id'],
    'favorite_food' => $favoriteFood,
    'cat_count' => $payload['cat_count'],
    'updated_favorite_food' => $favoriteFood,
    'updated_cat_count' => $payload['cat_count'],
  ]);

  respond(200, ['saved' => true]);
} catch (Throwable) {
  respond(500, ['error' => 'server_error']);
}