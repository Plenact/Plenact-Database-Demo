<?php
/**************************************************************************************************
 * @file       health.php
 * @brief      Return the fixed development API health response
 * @details    Preserve the original baseline health script for reference
 *
 * @author     Justin Reina
 * @created    10/01/26
 * @last rev   10/01/26
 *
 * @notes      Deploy Server/api-dev/health.php, not this baseline copy.
 *
 **************************************************************************************************/
declare(strict_types=1);


// -------------------------------------- MARK: - Response --------------------------------------- //

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

echo json_encode(
    [
        'service' => 'plenact-dev',
        'ok' => true,
    ],
    JSON_THROW_ON_ERROR
);