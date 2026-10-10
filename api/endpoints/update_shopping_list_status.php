<?php
// CORS headers
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

require_once '../config/db.php';

// Get POST data
$data = json_decode(file_get_contents('php://input'), true);
$userId = isset($data['userId']) ? intval($data['userId']) : 0;
$productId = isset($data['productId']) ? intval($data['productId']) : 0;
$productListId = isset($data['productListId']) ? intval($data['productListId']) : 0;
$status = isset($data['status']) ? intval($data['status']) : 0;

if (!$userId || !$status || !in_array($status, [1, 2, 3])) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing or invalid parameters']);
    exit;
}

try {
    // Update status for the item in the user's shopping list
    if ($productListId > 0) {
        $stmt = $pdo->prepare('UPDATE productLists SET status = ? WHERE ID = ? AND IDList = ?');
        $stmt->execute([$status, $productListId, $userId]);
    } else {
        if (!$productId) {
            http_response_code(400);
            echo json_encode(['error' => 'Missing productListId or productId']);
            exit;
        }
        $stmt = $pdo->prepare('UPDATE productLists SET status = ? WHERE IDList = ? AND IDProduct = ?');
        $stmt->execute([$status, $userId, $productId]);
    }
    if ($stmt->rowCount() > 0) {
        echo json_encode(['success' => true]);
    } else {
        http_response_code(404);
        echo json_encode(['error' => 'Item not found in shopping list']);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Server error', 'details' => $e->getMessage()]);
}
