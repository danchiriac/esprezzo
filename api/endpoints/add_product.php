<?php
// Enable error reporting for debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

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
require_user_type($pdo, $userId, $authToken, 2);
$productName = isset($data['productName']) ? $data['productName'] : '';
$brandId = isset($data['brandId']) ? $data['brandId'] : '';
$subcategoryId = isset($data['subcategoryId']) ? $data['subcategoryId'] : '';
$photo = 'no-image.png';
$barcode = isset($data['barcode']) ? $data['barcode'] : '';
$barcodeSearch = substr($barcode, -4);
$productName = isset($data['productName']) ? $data['productName'] : '';
$brandId = isset($data['brandId']) ? $data['brandId'] : '';
$subcategoryId = isset($data['subcategoryId']) ? $data['subcategoryId'] : '';
$quantity = isset($data['quantity']) ? $data['quantity'] : 0;
$quantityType = isset($data['quantityType']) ? $data['quantityType'] : '';
$weightUnit = isset($data['weightUnit']) ? $data['weightUnit'] : '';
$weightTotal = isset($data['weightTotal']) ? $data['weightTotal'] : 0;

if (!$barcode || !$productName || !$brandId || !$subcategoryId) {
    echo json_encode([
        'success' => false,
        'error' => 'Missing required fields',
        'debug' => [
            'barcode' => $barcode,
            'productName' => $productName,
            'brandId' => $brandId,
            'subcategoryId' => $subcategoryId,
            'input' => isset($data) ? $data : $_POST
        ]
    ]);
    exit;
}

// Add description
$descInsertQuery = "INSERT INTO descriptions (description, language, IDType) VALUES (?, 'ro', 1)";
$descStmt = $pdo->prepare($descInsertQuery);
$descStmt->execute([$productName]);
$idDescription = $pdo->lastInsertId();
$descUpdateQuery = 'UPDATE descriptions SET IDMatch = ? WHERE ID = ?';
$descStmt = $pdo->prepare($descUpdateQuery);
$descStmt->execute([$idDescription, $idDescription]);

// Insert product

$productInsertQuery = 'INSERT INTO products (productName, IDDescription, IDBrand, barcode, barcodeSearch, barcodeType, IDSubCategory, quantity, quantityType, weightUnit, weightTotal, photo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
$stmt = $pdo->prepare($productInsertQuery);
$success = $stmt->execute([
    $productName,
    $idDescription,
    $brandId,
    $barcode,
    $barcodeSearch,
    1, // Assuming 1 is the default barcode type, EAN-13
    $subcategoryId,
    $quantity,
    $quantityType,
    $weightUnit,
    $weightTotal,
    $photo
]);

if ($success) {
    echo json_encode([
        'success' => true,
        'productId' => $pdo->lastInsertId(),
        'debug' => [
            'input' => isset($data) ? $data : $_POST,
            'query' => $productInsertQuery,
            'params' => [
                $productName,
                $idDescription,
                $brandId,
                $barcode,
                $barcodeSearch,
                1,
                $subcategoryId,
                $quantity,
                $quantityType,
                $weightUnit,
                $weightTotal,
                $photo
            ]
        ]
    ]);
} else {
    echo json_encode([
        'success' => false,
        'error' => 'Failed to add product',
        'debug' => [
            'input' => isset($data) ? $data : $_POST,
            'query' => $productInsertQuery,
            'params' => [
                $productName,
                $idDescription,
                $brandId,
                $barcode,
                $barcodeSearch,
                1,
                $subcategoryId,
                $quantity,
                $quantityType,
                $weightUnit,
                $weightTotal,
                $photo
            ]
        ]
    ]);
}
