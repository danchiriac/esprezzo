<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$userId = isset($_GET['userId']) ? intval($_GET['userId']) : 0;
$userType = get_user_type($pdo, $userId);
if ($userType === null) {
    json_response(['success' => false, 'error' => 'User not found'], 404);
}

json_response(['success' => true, 'userType' => $userType]);
