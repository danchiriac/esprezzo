<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

require_once __DIR__ . '/../config/db.php';

$data = json_decode(file_get_contents('php://input'), true);
$userId = isset($data['userId']) ? intval($data['userId']) : 0;
$productId = isset($data['productId']) ? intval($data['productId']) : 0;
$productListId = isset($data['productListId']) ? intval($data['productListId']) : 0;
$tagId = isset($data['tagId']) ? intval($data['tagId']) : 0;
$status = isset($data['status']) ? intval($data['status']) : 1;
$quantity = isset($data['quantity']) ? intval($data['quantity']) : 0;

if ($userId <= 0 || $quantity <= 0 || !in_array($status, [1, 2], true)) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing or invalid parameters']);
    exit;
}

try {
    $listStmt = $pdo->prepare('SELECT ID FROM shoppingLists WHERE IDUser = ? LIMIT 1');
    $listStmt->execute([$userId]);
    $list = $listStmt->fetch(PDO::FETCH_ASSOC);

    if (!$list) {
        http_response_code(404);
        echo json_encode(['error' => 'Shopping list not found']);
        exit;
    }

    $listId = intval($list['ID']);

    $hasQuantityColumn = false;
    $columnStmt = $pdo->query("SHOW COLUMNS FROM productLists LIKE 'quantity'");
    if ($columnStmt && $columnStmt->fetch(PDO::FETCH_ASSOC)) {
        $hasQuantityColumn = true;
    }

    $identifierColumn = null;
    $identifierValue = null;
    if ($productListId > 0) {
        $identifierColumn = 'ID';
        $identifierValue = $productListId;
    } elseif ($tagId > 0) {
        $identifierColumn = 'IDTag';
        $identifierValue = $tagId;
    } elseif ($productId > 0) {
        $identifierColumn = 'IDProduct';
        $identifierValue = $productId;
    }

    if ($identifierColumn === null) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing item identifier']);
        exit;
    }

    if ($hasQuantityColumn) {
        $itemStmt = $pdo->prepare('SELECT ID FROM productLists WHERE IDList = ? AND ' . $identifierColumn . ' = ? AND status = ? ORDER BY ID ASC LIMIT 1');
        $itemStmt->execute([$listId, $identifierValue, $status]);
        $item = $itemStmt->fetch(PDO::FETCH_ASSOC);

        if (!$item) {
            if ($identifierColumn === 'IDTag') {
                $insertStmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, IDTag, status, dueDate, onlyPromo, quantity) VALUES (?, ?, ?, ?, NULL, 0, ?)');
                $success = $insertStmt->execute([$listId, $productId > 0 ? $productId : null, $identifierValue, $status, $quantity]);
            } else {
                $insertStmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, status, dueDate, onlyPromo, quantity) VALUES (?, ?, ?, NULL, 0, ?)');
                $success = $insertStmt->execute([$listId, $identifierValue, $status, $quantity]);
            }
        } else {
            $updateStmt = $pdo->prepare('UPDATE productLists SET quantity = ? WHERE ID = ?');
            $success = $updateStmt->execute([$quantity, $item['ID']]);
        }
    } else {
        $countStmt = $pdo->prepare('SELECT COUNT(*) AS itemCount FROM productLists WHERE IDList = ? AND ' . $identifierColumn . ' = ? AND status = ?');
        $countStmt->execute([$listId, $identifierValue, $status]);
        $currentQuantity = intval($countStmt->fetch(PDO::FETCH_ASSOC)['itemCount']);

        if ($currentQuantity === 0) {
            if ($identifierColumn === 'IDTag') {
                $insertStmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, IDTag, status, dueDate, onlyPromo) VALUES (?, ?, ?, ?, NULL, 0)');
            } else {
                $insertStmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, status, dueDate, onlyPromo) VALUES (?, ?, ?, NULL, 0)');
            }
            $success = true;
            for ($i = 0; $i < $quantity; $i++) {
                if ($identifierColumn === 'IDTag') {
                    $success = $insertStmt->execute([$listId, $productId > 0 ? $productId : null, $identifierValue, $status]) && $success;
                } else {
                    $success = $insertStmt->execute([$listId, $identifierValue, $status]) && $success;
                }
            }
        } elseif ($quantity > $currentQuantity) {
            if ($identifierColumn === 'IDTag') {
                $insertStmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, IDTag, status, dueDate, onlyPromo) VALUES (?, ?, ?, ?, NULL, 0)');
            } else {
                $insertStmt = $pdo->prepare('INSERT INTO productLists (IDList, IDProduct, status, dueDate, onlyPromo) VALUES (?, ?, ?, NULL, 0)');
            }
            $success = true;
            for ($i = 0; $i < ($quantity - $currentQuantity); $i++) {
                if ($identifierColumn === 'IDTag') {
                    $success = $insertStmt->execute([$listId, $productId > 0 ? $productId : null, $identifierValue, $status]) && $success;
                } else {
                    $success = $insertStmt->execute([$listId, $identifierValue, $status]) && $success;
                }
            }
        } elseif ($quantity < $currentQuantity) {
            $deleteStmt = $pdo->prepare('DELETE FROM productLists WHERE ID IN (SELECT ID FROM (SELECT ID FROM productLists WHERE IDList = ? AND ' . $identifierColumn . ' = ? AND status = ? ORDER BY ID DESC LIMIT ?) rows_to_delete)');
            $success = $deleteStmt->execute([$listId, $identifierValue, $status, $currentQuantity - $quantity]);
        } else {
            $success = true;
        }
    }

    if (!$success) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to update quantity']);
        exit;
    }

    echo json_encode(['success' => true, 'quantity' => $quantity]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Server error', 'details' => $e->getMessage()]);
}