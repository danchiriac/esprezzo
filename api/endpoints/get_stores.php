<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

require_once '../config/db.php';

$userId = isset($_GET['userid']) ? intval($_GET['userid']) : 0;
$stores = [];
$favorites = [];

if ($userId) {
    // Get favorite stores for user
    $favQuery = $pdo->prepare("SELECT s.ID, s.location, f.IDUser FROM stores s LEFT JOIN favoriteStores f ON s.ID = f.IDStore WHERE f.IDUser = ? ORDER BY s.location ASC");
    $favQuery->execute([$userId]);
    $favorites = $favQuery->fetchAll(PDO::FETCH_ASSOC);
}

// Get all stores (excluding favorites if user is logged in)
if ($userId && count($favorites) > 0) {
    $allQuery = $pdo->prepare("SELECT ID, location FROM stores WHERE ID NOT IN (SELECT IDStore FROM favoriteStores WHERE IDUser = ?) ORDER BY location ASC");
    $allQuery->execute([$userId]);
    $stores = $allQuery->fetchAll(PDO::FETCH_ASSOC);
} else {
    $allQuery = $pdo->query("SELECT ID, location FROM stores ORDER BY location ASC");
    $stores = $allQuery->fetchAll(PDO::FETCH_ASSOC);
}

// Combine favorites first, then others
$response = array_merge($favorites, $stores);
echo json_encode(['stores' => $response]);
