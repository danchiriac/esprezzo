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
$productId = isset($data['productId']) ? $data['productId'] : '';
$storeId = isset($data['storeId']) ? $data['storeId'] : '';
$price = isset($data['price']) ? $data['price'] : '';
$enGros = isset($data['enGros']) ? $data['enGros'] : 1;
$promo = !empty($data['promo']) ? intval($data['promo']) : 0;
$discountPrice = isset($data['discountPrice']) && $data['discountPrice'] !== '' ? $data['discountPrice'] : null;
$discountStart = isset($data['discountStart']) && $data['discountStart'] !== '' ? $data['discountStart'] : null;
$discountEnd = isset($data['discountEnd']) && $data['discountEnd'] !== '' ? $data['discountEnd'] : null;
$date = date('Y-m-d');

require_user_type($pdo, $userId, $authToken, 1);

if (!$productId || !$storeId || $price === '') {
    echo json_encode(['success' => false, 'error' => 'Missing required fields', 'debug' => $data]);
    exit;
}

// Check if price exists for this product, store, and quantity tier
$stmt = $pdo->prepare('SELECT ID FROM prices WHERE IDProduct = ? AND IDStore = ? AND enGros = ?');
$stmt->execute([$productId, $storeId, $enGros]);
$existing = $stmt->fetch();

if ($existing) {
    // Update price
    $insertStmt = $pdo->prepare('INSERT INTO pricesHistory (IdProduct, IdStore, price, enGros, date, inStock) SELECT IDProduct, IDStore, price, enGros, date, inStock FROM prices WHERE ID=?');
    $success = $insertStmt->execute([$existing['ID']]);
    $updateStmt = $pdo->prepare('UPDATE prices SET price = ?, date = ? WHERE IDProduct = ? AND IDStore = ? AND enGros = ?');
    $success = $updateStmt->execute([
        $price,
        $date,
        $productId,
        $storeId,
        $enGros
    ]);
    $priceId = $existing['ID'];
} else {
    // Insert new price
    $insertStmt = $pdo->prepare('INSERT INTO prices (IdProduct, IdStore, price, enGros, date, inStock) VALUES (?, ?, ?, ?, ?, 1)');
    $success = $insertStmt->execute([$productId, $storeId, $price, $enGros, $date]);
    $priceId = $pdo->lastInsertId();
}

if (!$success) {
    echo json_encode(['success' => false, 'error' => 'Failed to save base price']);
    exit;
}

if ($promo && $discountPrice !== null && $discountStart !== null && $discountEnd !== null) {
    $discountStmt = $pdo->prepare('SELECT ID FROM priceDiscounts WHERE IDPrice = ? AND typeDiscount = 1 AND discountStartDate = ? AND discountEndDate = ? LIMIT 1');
    $discountStmt->execute([$priceId, $discountStart, $discountEnd]);
    $existingDiscount = $discountStmt->fetch();

    if ($existingDiscount) {
        $discountUpdate = $pdo->prepare('UPDATE priceDiscounts SET price = ? WHERE ID = ?');
        $discountSuccess = $discountUpdate->execute([$discountPrice, $existingDiscount['ID']]);
        if (!$discountSuccess) {
            echo json_encode(['success' => false, 'error' => 'Failed to update discount']);
            exit;
        }
        echo json_encode([
            'success' => true,
            'action' => isset($existing['ID']) ? 'update' : 'insert',
            'priceId' => $priceId,
            'discountAction' => 'update_existing_dates',
            'date' => $date
        ]);
        exit;
    }

    $discountInsert = $pdo->prepare('INSERT INTO priceDiscounts (IDPrice, price, typeDiscount, discountStartDate, discountEndDate) VALUES (?, ?, 1, ?, ?)');
    $discountSuccess = $discountInsert->execute([$priceId, $discountPrice, $discountStart, $discountEnd]);
    if (!$discountSuccess) {
        echo json_encode(['success' => false, 'error' => 'Failed to insert discount']);
        exit;
    }

    echo json_encode([
        'success' => true,
        'action' => isset($existing['ID']) ? 'update' : 'insert',
        'priceId' => $priceId,
        'discountAction' => 'insert',
        'date' => $date
    ]);
    exit;
}

echo json_encode([
    'success' => true,
    'action' => isset($existing['ID']) ? 'update' : 'insert',
    'priceId' => $priceId,
    'discountAction' => 'unchanged',
    'date' => $date
]);
