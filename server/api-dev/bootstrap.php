<?php
/**************************************************************************************************
 * @file       bootstrap.php
 * @brief      Return app configuration, the active notice, and saved preferences
 * @details    Authenticate the app role before connecting to the development database
 *
 * @author     Justin Reina
 * @created    10/01/26
 * @last rev   10/01/26
 *
 * @notes      Preferences are scoped to the installation ID in private server configuration.
 *             Keep database credentials outside the public web root.
 *
 **************************************************************************************************/
declare(strict_types=1);


// -------------------------------------- MARK: - Runtime Settings ------------------------------ //

ini_set('display_errors', '0');

const JSON_DECODE_DEPTH          = 512;                                                            /* Maximum depth for JSON decoding                               */
const API_TOKEN_PATTERN          = '/\A[A-Za-z0-9]{64}\z/';                                        /* Pattern for validating API tokens                             */
const BEARER_TOKEN_PATTERN       = '/\ABearer ([A-Za-z0-9]{64})\z/i';                              /* Pattern for validating Bearer tokens                          */
const INSTALLATION_ID_PATTERN    = '/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/';   /* Pattern for validating installation IDs                       */
const PRIVATE_DIRECTORY_LEVELS   = 3;                                                              /* Levels to traverse to reach the private directory             */
const DATABASE_TIMEOUT_SECONDS   = 5;                                                              /* Timeout for database connections in seconds                   */
const WELCOME_CONFIGURATION_KEY  = 'welcome_message';                                              /* Key for retrieving the welcome message from the configuration */
const ACTIVE_NOTICE_VALUE        = 1;                                                              /* Value representing an active notice                           */
const LATEST_ACTIVE_NOTICE_LIMIT = 1;                                                              /* Maximum number of latest active notices to retrieve           */


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
 * @note       Never include credentials, paths, or internal exception details in responses.
 */
function respond(int $status, array $body): never
{
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');

  echo json_encode($body, JSON_THROW_ON_ERROR);
  exit;
}


// -------------------------------------- MARK: - Request And Authorization ---------------------- //

try {
  if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
    header('Allow: GET');
    respond(405, ['error' => 'method_not_allowed']);
  }

  $privateDirectory = dirname(__DIR__, PRIVATE_DIRECTORY_LEVELS);
  $authPath = $privateDirectory . '/plenact-private/api-auth.json';
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

  if (!isset($auth['installation_id'])
      || !is_string($auth['installation_id'])
      || preg_match(INSTALLATION_ID_PATTERN, $auth['installation_id']) !== 1) {
    throw new RuntimeException('Invalid installation identifier');
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
    'SELECT config_value, version
     FROM app_config
     WHERE config_key = :config_key'
  );
  $statement->execute(['config_key' => WELCOME_CONFIGURATION_KEY]);
  $configuration = $statement->fetch();

  if ($configuration === false) {
    throw new RuntimeException('Required configuration missing');
  }

  $statement = $pdo->prepare(
    'SELECT notice_id, message
     FROM notices
     WHERE is_active = :active
     ORDER BY notice_id DESC
     LIMIT ' . LATEST_ACTIVE_NOTICE_LIMIT
  );
  $statement->execute(['active' => ACTIVE_NOTICE_VALUE]);
  $notice = $statement->fetch();

  $statement = $pdo->prepare(
    'SELECT favorite_food, cat_count, gender, gender_description, is_excited
     FROM installation_preferences
      WHERE installation_id = :installation_id'
  );
  $statement->execute(['installation_id' => $auth['installation_id']]);
  $preferences = $statement->fetch();

  respond(200, [
    'configuration' => [
      'welcome_message' => $configuration['config_value'],
      'version' => (int) $configuration['version'],
    ],
    'notice' => $notice === false ? null : [
      'id' => (int) $notice['notice_id'],
      'message' => $notice['message'],
    ],
    'preferences' => $preferences === false ? null : [
      'favorite_food' => $preferences['favorite_food'],
      'cat_count' => (int) $preferences['cat_count'],
      'gender' => $preferences['gender'],
      'gender_description' => $preferences['gender_description'],
      'is_excited' => (bool) $preferences['is_excited'],
    ],
  ]);
} catch (Throwable) {
  respond(500, ['error' => 'server_error']);
}