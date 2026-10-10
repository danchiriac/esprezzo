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

$storeId = isset($_GET['storeId']) ? intval($_GET['storeId']) : 0;
if ($storeId <= 0) {
    json_response(['error' => 'Missing or invalid storeId'], 400);
}

try {
    $stmt = $pdo->prepare('SELECT p.ID AS productId, p.productName, p.photo, s.ID AS storeId, s.location AS store, pr.ID AS priceId, pr.price AS originalPrice, pd.price AS promoPrice, pr.enGros, pr.inStock, pr.date AS priceDate FROM prices pr INNER JOIN products p ON p.ID = pr.IDProduct INNER JOIN stores s ON s.ID = pr.IDStore LEFT JOIN priceDiscounts pd ON pd.IDPrice = pr.ID AND pd.discountStartDate <= DATE(NOW()) AND pd.discountEndDate >= DATE(NOW()) WHERE pr.IDStore = ? AND pr.price > 0 ORDER BY pr.date ASC, p.productName ASC, pr.enGros ASC');
    $stmt->execute([$storeId]);
    json_response(['products' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
} catch (PDOException $e) {
    json_response(['error' => 'Failed to load store prices'], 500);
}
