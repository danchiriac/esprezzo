<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Allow CORS for local web debugging - remove after development
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}
// endpoints/auth.php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

// Example: login (POST: email, password)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $email = isset($input['email']) ? $input['email'] : '';
    $password = isset($input['password']) ? $input['password'] : '';
    error_log('auth.php email=' . var_export($email, true));
    $stmt = $pdo->prepare('SELECT ID, passwordHash, userType FROM users WHERE email = ?');
    $stmt->execute([$email]);
    $user = $stmt->fetch();
    if ($user && password_verify($password, $user['passwordHash'])) {
        json_response([
            'success' => true,
            'userId' => $user['ID'],
            'userType' => (int) (isset($user['userType']) ? $user['userType'] : 0),
            'authToken' => create_auth_token($user['ID'], $user['passwordHash'])
        ]);
    } else {
        json_response(['error' => 'Invalid credentials'], 401);
    }
} else {
    json_response(['error' => 'Invalid request'], 400);
}
?>
