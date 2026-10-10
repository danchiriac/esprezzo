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

$userId = isset($_GET['userid']) ? intval($_GET['userid']) : 0;
$listName = isset($_GET['listname']) ? trim($_GET['listname']) : 'Lista cumparaturi';
if ($userId <= 0) {
    json_response(['error' => 'Missing userId'], 400);
}
// Find the shopping list
$stmt = $pdo->prepare('SELECT ID FROM shoppingLists WHERE IDUser = ?');
$stmt->execute([$userId]);
$list = $stmt->fetch();
if (!$list) {
    json_response(['products' => []]);
}
$listId = $list['ID'];

$hasQuantityColumn = false;
$columnStmt = $pdo->query("SHOW COLUMNS FROM productLists LIKE 'quantity'");
if ($columnStmt && $columnStmt->fetch()) {
    $hasQuantityColumn = true;
}

// Get products in the list
$quantitySql = $hasQuantityColumn
    ? 'SUM(CASE WHEN pl.quantity IS NULL OR pl.quantity <= 0 THEN 1 ELSE pl.quantity END)'
    : 'COUNT(*)';

$stmt = $pdo->prepare('SELECT MIN(pl.ID) as productListId, MIN(pl.IDTag) as tagId, pl.status, MAX(pl.dueDate) as dueDate, MAX(pl.onlyPromo) as onlyPromo, MIN(pl.IDProduct) as productId, p.productName, p.photo, t.tag as tagName, ' . $quantitySql . ' as quantity FROM productLists pl LEFT JOIN products p ON pl.IDProduct = p.ID LEFT JOIN tags t ON pl.IDTag = t.ID WHERE pl.IDList = ? and pl.status <= 2 GROUP BY pl.status, pl.IDProduct, pl.IDTag, p.productName, p.photo, t.tag ORDER BY pl.status asc, COALESCE(p.productName, t.tag) asc');
$stmt->execute([$listId]);
$products = $stmt->fetchAll();

$productIds = [];
foreach ($products as $product) {
    $productId = intval($product['productId']);
    if ($productId > 0) {
        $productIds[] = $productId;
    }
}

$pricesByProduct = [];
if (count($productIds) > 0) {
    $placeholders = implode(',', array_fill(0, count($productIds), '?'));
    $pricesStmt = $pdo->prepare('SELECT p.IDProduct, p.ID as priceId, p.IDStore as storeId, s.location as store, p.price, p.enGros, p.date, p.inStock, pd.price as discountedPrice, pd.typeDiscount, IFNULL(pd.price, p.price) as actualPrice FROM prices as p INNER JOIN stores s ON s.ID = p.IDStore LEFT JOIN priceDiscounts as pd ON pd.IDPrice = p.ID AND pd.discountStartDate <= DATE(NOW()) AND pd.discountEndDate >= DATE(NOW()) WHERE p.IDProduct IN (' . $placeholders . ') ORDER BY p.IDProduct, s.location ASC, p.IDStore, p.enGros ASC, actualPrice ASC');
    $pricesStmt->execute($productIds);
    $priceRows = $pricesStmt->fetchAll();

    foreach ($priceRows as $price) {
        if ($price['price'] == 0 || $price['actualPrice'] == 0) {
            continue;
        }

        $productId = intval($price['IDProduct']);
        if (!isset($pricesByProduct[$productId])) {
            $pricesByProduct[$productId] = [];
        }

        $pricesByProduct[$productId][] = [
            'storeId' => $price['storeId'],
            'store' => $price['store'],
            'price' => $price['price'],
            'actualPrice' => $price['actualPrice'],
            'discountedPrice' => $price['discountedPrice'],
            'typeDiscount' => $price['typeDiscount'],
            'enGros' => $price['enGros'],
            'date' => $price['date'],
            'priceId' => $price['priceId'],
            'inStock' => $price['inStock']
        ];
    }
}

foreach ($products as &$product) {
    $productId = intval($product['productId']);
    $product['tagId'] = isset($product['tagId']) ? intval($product['tagId']) : 0;
    if ((!isset($product['productName']) || $product['productName'] === null || $product['productName'] === '') && isset($product['tagName'])) {
        $product['productName'] = $product['tagName'];
    }
    $product['prices'] = isset($pricesByProduct[$productId]) ? $pricesByProduct[$productId] : [];
}
unset($product);

json_response(['products' => $products]);
