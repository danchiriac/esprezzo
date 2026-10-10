<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type');

$userId = isset($_GET['userId']) ? intval($_GET['userId']) : null;

if (!$userId || $userId <= 0) {
    json_response(['error' => 'Invalid userId'], 400);
    exit;
}

try {
    // Get favorite products for the user with category info
    $stmt = $pdo->prepare('
        SELECT 
            p.ID, 
            p.productName, 
            p.photo, 
            p.barcode,
            psc.subcategory,
            pc.category
        FROM favorites f
        INNER JOIN products p ON p.ID = f.IDProduct
        INNER JOIN productSubCategories psc ON psc.ID = p.IDSubCategory
        INNER JOIN productCategories pc ON pc.ID = psc.IDCategory
        WHERE f.IDUser = ?
        ORDER BY p.productName ASC
    ');
    $stmt->execute([$userId]);
    $products = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    json_response(['products' => $products]);
} catch (Exception $e) {
    json_response(['error' => $e->getMessage()], 500);
}
?>
