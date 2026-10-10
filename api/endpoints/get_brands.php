<?php
require_once '../config/db.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$stmt = $pdo->query('SELECT ID, brand FROM brands ORDER BY brand');
$brands = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode(['brands' => $brands]);
