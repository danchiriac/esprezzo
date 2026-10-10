<?php
// Allow CORS for local web debugging
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// POST: Add product to shopping list
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode(file_get_contents('php://input'), true);
    $userId = isset($data['userId']) ? intval($data['userId']) : 0;
    $productId = isset($data['productId']) ? intval($data['productId']) : 0;
    $tagId = isset($data['tagId']) ? intval($data['tagId']) : 0;
    $storeId = isset($data['storeId']) ? intval($data['storeId']) : 0;
    $listName = isset($data['listName']) ? trim($data['listName']) : 'Lista cumparaturi';
    if ($userId <= 0 || ($productId <= 0 && $tagId <= 0)) {
        json_response(['error' => 'Missing userId and item identifier'], 400);
    }
    // Find or create shopping list
    $stmt = $pdo->prepare('SELECT ID FROM shoppingLists WHERE IDUser = ?');
    $stmt->execute([$userId]);
    $list = $stmt->fetch();
    if (!$list) {
        $stmt = $pdo->prepare('INSERT INTO shoppingLists (listName, IDUser, IDStore) VALUES (?, ?, ?)');
        $stmt->execute([$listName, $userId, $storeId]);
        $listId = $pdo->lastInsertId();
    } else {
        $listId = $list['ID'];
    }

    $hasQuantityColumn = false;
    $columnStmt = $pdo->query("SHOW COLUMNS FROM productLists LIKE 'quantity'");
    if ($columnStmt && $columnStmt->fetch()) {
        $hasQuantityColumn = true;
    }

    if ($hasQuantityColumn) {
        if ($tagId > 0) {
            $stmt = $pdo->prepare('SELECT ID, quantity FROM productLists WHERE IDList = ? AND IDTag = ? AND status = 1 LIMIT 1');
            $stmt->execute([$listId, $tagId]);
        } else {
            $stmt = $pdo->prepare('SELECT ID, quantity FROM productLists WHERE IDList = ? AND IDProduct = ? AND status = 1 LIMIT 1');
            $stmt->execute([$listId, $productId]);
        }
        $existing = $stmt->fetch();

        if ($existing) {
            $currentQuantity = isset($existing['quantity']) ? intval($existing['quantity']) : 1;
            $updateStmt = $pdo->prepare('UPDATE productLists SET quantity = ? WHERE ID = ?');
            $updateStmt->execute([$currentQuantity + 1, $existing['ID']]);
        } else {
            if ($tagId > 0) {
                $stmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, IDTag, status, dueDate, onlyPromo, quantity) VALUES (?, ?, ?, 1, NULL, 0, 1)');
                $stmt->execute([$listId, $productId > 0 ? $productId : 0, $tagId]);
            } else {
                $stmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, status, dueDate, onlyPromo, quantity) VALUES (?, ?, 1, NULL, 0, 1)');
                $stmt->execute([$listId, $productId]);
            }
        }
    } else {
        // Add product to productLists; duplicate rows are interpreted as quantity > 1.
        if ($tagId > 0) {
            $stmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, IDTag, status, dueDate, onlyPromo) VALUES (?, ?, ?, 1, NULL, 0)');
            $stmt->execute([$listId, $productId > 0 ? $productId : 0, $tagId]);
        } else {
            $stmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, status, dueDate, onlyPromo) VALUES (?, ?, 1, NULL, 0)');
            $stmt->execute([$listId, $productId]);
        }
    }

    json_response(['success' => true, 'listId' => $listId]);
} else {
    json_response(['error' => 'Invalid request'], 400);
}
