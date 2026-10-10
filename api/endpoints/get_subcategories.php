<?php
require_once '../config/db.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Use isset() for compatibility with older PHP versions
$categoryId = isset($_GET['categoryId']) ? $_GET['categoryId'] : '';
if (!$categoryId) {
    echo json_encode(['subcategories' => []]);
    exit;
}
$stmt = $pdo->prepare('SELECT ID, subcategory FROM productSubCategories WHERE IDCategory = ? ORDER BY subcategory');
$stmt->execute([$categoryId]);
$subcategories = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode(['subcategories' => $subcategories]);
