<?php
require_once '../config/db.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Use isset() for compatibility with older PHP versions
$mainCategoryId = isset($_GET['mainCategoryId']) ? $_GET['mainCategoryId'] : '';
if (!$mainCategoryId) {
    echo json_encode(['categories' => []]);
    exit;
}
$sql = 'SELECT ID, category FROM productCategories WHERE IDMainCategory = ? ORDER BY category';
$stmt = $pdo->prepare($sql);
$success = $stmt->execute([$mainCategoryId]);
$categories = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode(['categories' => $categories]);
