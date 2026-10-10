<?php
$localConfigPath = __DIR__ . '/db.local.php';
if (!is_file($localConfigPath)) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Local database configuration is missing']);
    exit;
}

require_once $localConfigPath;
