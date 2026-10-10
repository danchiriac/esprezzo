<?php
require_once '../config/db.php';
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
$userId = isset($data['userId']) ? $data['userId'] : 0;
$authToken = isset($data['authToken']) ? $data['authToken'] : '';
$priceId = isset($data['priceId']) ? $data['priceId'] : '';

require_user_type($pdo, $userId, $authToken, 1);

if (!$priceId) {
    echo json_encode(['success' => false, 'error' => 'Missing priceId']);
    exit;
}

try {
    // Delete the price record
    $stmt = $pdo->prepare('DELETE FROM prices WHERE ID = ?');
    $success = $stmt->execute([$priceId]);
    
    if ($success) {
        echo json_encode(['success' => true, 'action' => 'delete']);
    } else {
        echo json_encode(['success' => false, 'error' => 'Failed to delete price']);
    }
} catch (Exception $e) {
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
?>
