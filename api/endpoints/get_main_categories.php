<?php
require_once '../config/db.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$stmt = $pdo->query('SELECT ID, mainCategory FROM productMainCategories ORDER BY mainCategory');
$mainCategories = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode(['mainCategories' => $mainCategories]);
