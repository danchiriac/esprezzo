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

try {
    $stmt = $pdo->prepare('SELECT p.ID AS productId, p.productName, p.photo, s.ID AS storeId, s.location AS store, pr.price AS originalPrice, pd.price AS promoPrice, pd.typeDiscount, pd.discountStartDate AS startDate, pd.discountEndDate AS endDate, pr.enGros, pr.inStock FROM priceDiscounts pd INNER JOIN prices pr ON pr.ID = pd.IDPrice INNER JOIN products p ON p.ID = pr.IDProduct INNER JOIN stores s ON s.ID = pr.IDStore WHERE pd.discountStartDate <= DATE(NOW()) AND pd.discountEndDate >= DATE(NOW()) AND pd.price > 0 AND pr.price > 0 ORDER BY pd.discountEndDate ASC, p.productName ASC, s.location ASC, pr.enGros ASC');
    $stmt->execute();
    json_response(['promotions' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
} catch (PDOException $e) {
    json_response(['error' => 'Failed to load promotions'], 500);
}
