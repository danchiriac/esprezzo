<?php
// get_brand_categories.php
require_once '../config/db.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$brandId = isset($_GET['brandId']) ? intval($_GET['brandId']) : 0;
$response = [
    'IDMainCategory' => null,
    'IDCategory' => null,
    'IDSubCategory' => null,
];

if ($brandId > 0) {
    $sql = "SELECT IDMainCategory, IDCategory, IDSubCategory FROM brandsCategories WHERE IDBrand = ? LIMIT 1";
    $stmt = $pdo->prepare($sql);
    $success = $stmt->execute([$brandId]);
    if ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $response['IDMainCategory'] = intval($row['IDMainCategory']);
        $response['IDCategory'] = intval($row['IDCategory']);
        $response['IDSubCategory'] = intval($row['IDSubCategory']);
    }
}

echo json_encode($response);
