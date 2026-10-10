<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

$productId = isset($_GET['productId']) ? intval($_GET['productId']) : 0;
if ($productId <= 0) {
    json_response(['error' => 'Invalid product ID'], 400);
}

$stmt = $pdo->prepare(
    'SELECT priceHistory.price, priceHistory.enGros, priceHistory.date, stores.ID AS storeId, stores.location AS store
     FROM pricesHistory AS priceHistory
     INNER JOIN stores ON stores.ID = priceHistory.IdStore
     WHERE priceHistory.IdProduct = ?
     UNION ALL
     SELECT currentPrice.price, currentPrice.enGros, currentPrice.date, stores.ID AS storeId, stores.location AS store
     FROM prices AS currentPrice
     INNER JOIN stores ON stores.ID = currentPrice.IdStore
     WHERE currentPrice.IdProduct = ?
     ORDER BY date ASC, store ASC, enGros ASC'
);
$stmt->execute([$productId, $productId]);

json_response(['history' => $stmt->fetchAll()]);