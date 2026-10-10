<?php
// CORS headers
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
require_once '../config/db.php';
header('Content-Type: application/json');

$data = json_decode(file_get_contents('php://input'), true);
$userId = isset($data['userId']) ? intval($data['userId']) : 0;
$productId = isset($data['productId']) ? intval($data['productId']) : 0;

if ($userId <= 0 || $productId <= 0) {
    echo json_encode(['success' => false, 'error' => 'Missing userId or productId']);
    exit;
}

try {
    $stmt = $pdo->prepare('DELETE FROM favorites WHERE IDUser = ? AND IDProduct = ?');
    $stmt->execute([$userId, $productId]);
    echo json_encode(['success' => true]);
} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
