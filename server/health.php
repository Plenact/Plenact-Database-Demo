<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

echo json_encode([
    'service' => 'plenact-dev',
    'ok' => true
], JSON_THROW_ON_ERROR);