<?php
/**************************************************************************************************
 * @file       planner.php
 * @brief      Load or replace the demo Planner snapshot
 * @details    Store one authenticated JSON document per configured installation
 *
 * @author     Justin Reina
 * @created    10/02/26
 * @last rev   10/02/26
 *
 * @notes      Demonstration endpoint with last-write-wins behavior and no revision history.
 *             Production ownership must come from an authenticated user or organization.
 *
 **************************************************************************************************/
declare(strict_types=1);


// -------------------------------------- MARK: - Runtime Settings ------------------------------ //

ini_set('display_errors', '0');

const JSON_DECODE_DEPTH = 512;
const API_TOKEN_PATTERN = '/\A[A-Za-z0-9]{64}\z/';
const BEARER_TOKEN_PATTERN = '/\ABearer ([A-Za-z0-9]{64})\z/i';
const INSTALLATION_ID_PATTERN = '/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/';
const PRIVATE_DIRECTORY_LEVELS = 3;
const DATABASE_TIMEOUT_SECONDS = 5;
const PLANNER_SCHEMA_VERSION = 1;
const MAX_PLANNER_REQUEST_BYTES = 65536;
const DAY_SLOT_COUNT = 7;
const MIN_EVENT_TIME_OF_DAY = 0;
const MAX_EVENT_TIME_OF_DAY = 1439;


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
 * @note       Do not include credentials, paths, or internal exceptions in response bodies.
 */
function respond(int $status, array $body): never
{
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store');

  echo json_encode($body, JSON_THROW_ON_ERROR);
  exit;
}


// -------------------------------------- MARK: - Planner Validation ---------------------------- //

/**
 * @fcn        is_nonempty_text
 * @brief      Check that a value is valid UTF-8 text with visible content.
 * @param[in]  $value  Untrusted JSON value.
 * @return     (bool) true for a nonempty string without control characters.
 */
function is_nonempty_text(mixed $value): bool
{
  if (!is_string($value) || preg_match('//u', $value) !== 1) {
    return false;
  }

  $text = trim($value);

  return $text !== ''
    && preg_match('/\A[^\x00-\x1F\x7F]+\z/u', $text) === 1;
}

/**
 * @fcn        has_unique_item_id
 * @brief      Validate and register a positive item ID within the snapshot.
 * @param[in]  $item  Candidate nested Planner object.
 * @param[in,out] $seen_ids IDs already used in this Planner document.
 * @return     (bool) true when the item has a unique positive integer ID.
 */
function has_unique_item_id(mixed $item, array &$seen_ids): bool
{
  if (!is_array($item)
      || !isset($item['id'])
      || !is_int($item['id'])
      || $item['id'] < 1
      || isset($seen_ids[$item['id']])) {
    return false;
  }

  $seen_ids[$item['id']] = true;

  return true;
}

/**
 * @fcn        validate_planner_document
 * @brief      Validate the supported Planner v1 snapshot shape and values.
 * @details    Reject malformed nested arrays before opening the database connection.
 * @param[in]  $planner  Decoded JSON request value.
 * @return     (bool) true when the document conforms to the v1 contract.
 */
function validate_planner_document(mixed $planner): bool
{
  if (!is_array($planner)
      || ($planner['schema_version'] ?? null) !== PLANNER_SCHEMA_VERSION
      || !isset($planner['week_plan'], $planner['life_plan'], $planner['notes'])
      || !is_array($planner['week_plan'])
      || !is_array($planner['life_plan'])
      || !is_array($planner['week_plan']['days'] ?? null)
      || !array_is_list($planner['week_plan']['days'])
      || count($planner['week_plan']['days']) !== DAY_SLOT_COUNT
      || !is_array($planner['notes'])
      || !array_is_list($planner['notes'])) {
    return false;
  }

  $seen_ids = [];

  foreach ($planner['week_plan']['days'] as $day_index => $day) {
    if (!is_array($day)
        || ($day['day_index'] ?? null) !== $day_index
        || !is_array($day['goals'] ?? null)
        || !array_is_list($day['goals'])
        || !is_array($day['schedules'] ?? null)
        || !array_is_list($day['schedules'])
        || !is_array($day['cards'] ?? null)
        || !array_is_list($day['cards'])) {
      return false;
    }

    foreach ($day['goals'] as $goal) {
      if (!has_unique_item_id($goal, $seen_ids)
          || !is_nonempty_text($goal['description'] ?? null)
          || !is_int($goal['priority'] ?? null)) {
        return false;
      }
    }

    foreach ($day['schedules'] as $schedule) {
      if (!has_unique_item_id($schedule, $seen_ids)
          || !is_array($schedule['events'] ?? null)
          || !array_is_list($schedule['events'])) {
        return false;
      }

      foreach ($schedule['events'] as $event) {
        if (!has_unique_item_id($event, $seen_ids)
            || !is_int($event['time_of_day_minutes'] ?? null)
            || $event['time_of_day_minutes'] < MIN_EVENT_TIME_OF_DAY
            || $event['time_of_day_minutes'] > MAX_EVENT_TIME_OF_DAY
            || !is_nonempty_text($event['description'] ?? null)) {
          return false;
        }
      }
    }

    foreach ($day['cards'] as $card) {
      if (!has_unique_item_id($card, $seen_ids)
          || !is_nonempty_text($card['title'] ?? null)
          || !is_int($card['value'] ?? null)
          || !is_nonempty_text($card['name'] ?? null)) {
        return false;
      }
    }
  }

  if (!is_array($planner['life_plan']['goals'] ?? null)
      || !array_is_list($planner['life_plan']['goals'])
      || !is_array($planner['life_plan']['milestones'] ?? null)
      || !array_is_list($planner['life_plan']['milestones'])) {
    return false;
  }

  foreach ($planner['life_plan']['goals'] as $goal) {
    if (!has_unique_item_id($goal, $seen_ids)
        || !is_nonempty_text($goal['description'] ?? null)
        || !is_int($goal['priority'] ?? null)) {
      return false;
    }
  }

  foreach ($planner['life_plan']['milestones'] as $milestone) {
    if (!has_unique_item_id($milestone, $seen_ids)
        || !is_nonempty_text($milestone['description'] ?? null)
        || !is_nonempty_text($milestone['category'] ?? null)
        || !is_string($milestone['notes'] ?? null)
        || preg_match('//u', $milestone['notes']) !== 1) {
      return false;
    }
  }

  foreach ($planner['notes'] as $note) {
    if (!has_unique_item_id($note, $seen_ids)
        || !is_string($note['text'] ?? null)
        || preg_match('//u', $note['text']) !== 1) {
      return false;
    }
  }

  return true;
}


// -------------------------------------- MARK: - Request And Authorization ---------------------- //

try {
  $request_method = $_SERVER['REQUEST_METHOD'] ?? '';

  if (!in_array($request_method, ['GET', 'PUT'], true)) {
    header('Allow: GET, PUT');
    respond(405, ['error' => 'method_not_allowed']);
  }

  $private_directory = dirname(__DIR__, PRIVATE_DIRECTORY_LEVELS);
  $auth_path = $private_directory . '/plenact-private/api-auth.json';
  $auth_json = @file_get_contents($auth_path);

  if ($auth_json === false) {
    throw new RuntimeException('Authentication configuration unavailable');
  }

  $auth = json_decode($auth_json, true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR);

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
      || preg_match(INSTALLATION_ID_PATTERN, $auth['installation_id'] ?? '') !== 1) {
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


  // -------------------------------------- MARK: - Request Validation -------------------------- //

  $planner_json = null;

  if ($request_method === 'PUT') {
    $content_type = strtolower(trim(explode(
      ';',
      $_SERVER['CONTENT_TYPE'] ?? ''
    )[0]));

    if ($content_type !== 'application/json') {
      respond(415, ['error' => 'unsupported_media_type']);
    }

    $raw_body = file_get_contents('php://input');

    if ($raw_body === false || $raw_body === '') {
      respond(400, ['error' => 'invalid_json']);
    }

    if (strlen($raw_body) > MAX_PLANNER_REQUEST_BYTES) {
      respond(413, ['error' => 'request_too_large']);
    }

    try {
      $planner = json_decode($raw_body, true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
      respond(400, ['error' => 'invalid_json']);
    }

    if (!validate_planner_document($planner)) {
      respond(422, ['error' => 'invalid_planner_document']);
    }

    $planner_json = json_encode($planner, JSON_THROW_ON_ERROR);
  }


  // -------------------------------------- MARK: - Database Access ----------------------------- //

  $database_path = $private_directory . '/plenact-private/database.json';
  $database_json = @file_get_contents($database_path);

  if ($database_json === false) {
    throw new RuntimeException('Database configuration unavailable');
  }

  $database = json_decode($database_json, true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR);

  foreach (['host', 'database', 'username', 'password'] as $key) {
    if (!isset($database[$key])
        || !is_string($database[$key])
        || $database[$key] === '') {
      throw new RuntimeException('Invalid database configuration');
    }
  }

  $pdo = new PDO(
    "mysql:host={$database['host']};dbname={$database['database']};charset=utf8mb4",
    $database['username'],
    $database['password'],
    [
      PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
      PDO::ATTR_EMULATE_PREPARES => false,
      PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
      PDO::ATTR_TIMEOUT => DATABASE_TIMEOUT_SECONDS,
    ]
  );

  if ($request_method === 'GET') {
    $statement = $pdo->prepare(
      'SELECT planner_document, created_at, updated_at
       FROM installation_planner
       WHERE installation_id = :installation_id'
    );
    $statement->execute(['installation_id' => $auth['installation_id']]);
    $row = $statement->fetch();

    if ($row === false) {
      respond(200, [
        'planner' => null,
        'created_at' => null,
        'updated_at' => null,
      ]);
    }

    respond(200, [
      'planner' => json_decode($row['planner_document'], true, JSON_DECODE_DEPTH, JSON_THROW_ON_ERROR),
      'created_at' => $row['created_at'],
      'updated_at' => $row['updated_at'],
    ]);
  }

  $statement = $pdo->prepare(
    'INSERT INTO installation_planner (
      installation_id,
      planner_document,
      created_at,
      updated_at
    ) VALUES (
      :installation_id,
      :planner_document,
      UTC_TIMESTAMP(6),
      UTC_TIMESTAMP(6)
    )
    ON DUPLICATE KEY UPDATE
      planner_document = :updated_planner_document,
      updated_at = UTC_TIMESTAMP(6)'
  );
  $statement->execute([
    'installation_id' => $auth['installation_id'],
    'planner_document' => $planner_json,
    'updated_planner_document' => $planner_json,
  ]);

  $statement = $pdo->prepare(
    'SELECT created_at, updated_at
     FROM installation_planner
     WHERE installation_id = :installation_id'
  );
  $statement->execute(['installation_id' => $auth['installation_id']]);
  $timestamps = $statement->fetch();

  respond(200, [
    'saved' => true,
    'created_at' => $timestamps['created_at'],
    'updated_at' => $timestamps['updated_at'],
  ]);
} catch (Throwable) {
  respond(500, ['error' => 'server_error']);
}
