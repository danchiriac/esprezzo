<?php
// CORS headers
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
require_once '../config/db.php'; // Adjust path as needed

function haversineGreatCircleDistance($lat1, $lon1, $lat2, $lon2, $earthRadius = 6371000) {
    // Convert from degrees to radians
    $lat1 = deg2rad($lat1);
    $lon1 = deg2rad($lon1);
    $lat2 = deg2rad($lat2);
    $lon2 = deg2rad($lon2);
    $latDelta = $lat2 - $lat1;
    $lonDelta = $lon2 - $lon1;
    $a = sin($latDelta / 2) * sin($latDelta / 2) +
        cos($lat1) * cos($lat2) *
        sin($lonDelta / 2) * sin($lonDelta / 2);
    $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
    return $earthRadius * $c;
}

$lat = isset($_GET['lat']) ? floatval($_GET['lat']) : null;
$lng = isset($_GET['lng']) ? floatval($_GET['lng']) : null;
$radius = isset($_GET['radius']) ? floatval($_GET['radius']) : 200;

if ($lat === null || $lng === null) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing lat/lng']);
    exit;
}

// Find all GPS positions within radius
$sql = "SELECT ID, latitude, longitude FROM storeGPSPositions where POW((latitude-?), 2)+POW((longitude-?), 2)<0.0001";
$stmt = $pdo->prepare($sql);
$stmt->execute([$lat, $lng]);
$foundId = null;
$foundIdMin = null;
$distanceMin = 0;
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $distance = haversineGreatCircleDistance($lat, $lng, $row['latitude'], $row['longitude']);
    if ($distanceMin == 0 || $distance < $distanceMin) {
        $distanceMin = $distance;
        $foundIdMin = $row['ID'];
    }
}
if ($distanceMin <= $radius) {
    $foundId = $foundIdMin;
}

if ($foundId) {
    // Find store with this GPS position
    $sql2 = "SELECT ID FROM stores WHERE IDGPSPosition = ? LIMIT 1";
    $stmt = $pdo->prepare($sql2);
    $stmt->execute([$foundId]);
    if ($store = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo json_encode(['storeId' => $store['ID'], 'distance' => $distanceMin]);
        exit;
    }
}

echo json_encode(['storeId' => null, 'distance' => 0]);
