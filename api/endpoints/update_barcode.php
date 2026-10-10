<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);
$userId = isset($data['userId']) ? intval($data['userId']) : 0;
$authToken = isset($data['authToken']) ? $data['authToken'] : '';
$productId = isset($data['productId']) ? intval($data['productId']) : 0;
$barcode = isset($data['barcode']) ? trim((string) $data['barcode']) : '';

require_user_type($pdo, $userId, $authToken, 2);

if ($productId <= 0 || !preg_match('/^[0-9]+$/', $barcode)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Invalid productId or barcode']);
    exit;
}

try {
    $productStmt = $pdo->prepare('SELECT ID FROM products WHERE ID = ?');
    $productStmt->execute([$productId]);
    if (!$productStmt->fetch()) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Product not found']);
        exit;
    }

    $barcodeSearch = substr($barcode, -4);
    $updateStmt = $pdo->prepare('UPDATE products SET barcode = ?, barcodeSearch = ? WHERE ID = ?');
    $updateStmt->execute([$barcode, $barcodeSearch, $productId]);

    echo json_encode([
        'success' => true,
        'barcode' => $barcode,
        'barcodeSearch' => $barcodeSearch
    ]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'Failed to update barcode']);
}
