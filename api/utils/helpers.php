<?php
// utils/helpers.php
function json_response($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}

function get_user_type($pdo, $userId) {
    $userId = filter_var($userId, FILTER_VALIDATE_INT);
    if ($userId === false || $userId <= 0) {
        return null;
    }

    $stmt = $pdo->prepare('SELECT userType FROM users WHERE ID = ?');
    $stmt->execute([$userId]);
    $user = $stmt->fetch();
    return $user ? (int) (isset($user['userType']) ? $user['userType'] : 0) : null;
}

function create_auth_token($userId, $passwordHash) {
    $payload = intval($userId) . ':' . (time() + 30 * 24 * 60 * 60);
    $signature = hash_hmac('sha256', $payload, $passwordHash);
    return rtrim(strtr(base64_encode($payload . ':' . $signature), '+/', '-_'), '=');
}

function has_valid_auth_token($pdo, $userId, $authToken) {
    $userId = filter_var($userId, FILTER_VALIDATE_INT);
    if ($userId === false || $userId <= 0 || !is_string($authToken) || $authToken === '') {
        return false;
    }

    $encodedToken = strtr($authToken, '-_', '+/');
    $encodedToken .= str_repeat('=', (4 - strlen($encodedToken) % 4) % 4);
    $decodedToken = base64_decode($encodedToken, true);
    if ($decodedToken === false) {
        return false;
    }

    $parts = explode(':', $decodedToken);
    if (count($parts) !== 3 || intval($parts[0]) !== $userId || intval($parts[1]) < time()) {
        return false;
    }

    $stmt = $pdo->prepare('SELECT passwordHash FROM users WHERE ID = ?');
    $stmt->execute([$userId]);
    $user = $stmt->fetch();
    if (!$user || empty($user['passwordHash'])) {
        return false;
    }

    $expectedSignature = hash_hmac('sha256', $parts[0] . ':' . $parts[1], $user['passwordHash']);
    return hash_equals($expectedSignature, $parts[2]);
}

function require_user_type($pdo, $userId, $authToken, $minimumUserType) {
    if (!has_valid_auth_token($pdo, $userId, $authToken)) {
        json_response(['success' => false, 'error' => 'Authentication required'], 401);
    }

    $userType = get_user_type($pdo, $userId);
    if ($userType === null) {
        json_response(['success' => false, 'error' => 'Authentication required'], 401);
    }
    if ($userType < $minimumUserType) {
        json_response(['success' => false, 'error' => 'Insufficient permissions'], 403);
    }

    return $userType;
}

function utf8_strtolower($text) {
    $text = (string) $text;

    if (function_exists('mb_strtolower')) {
        return mb_strtolower($text, 'UTF-8');
    }

    $text = strtr($text, [
        'Ă' => 'ă',
        'Â' => 'â',
        'Î' => 'î',
        'Ș' => 'ș',
        'Ş' => 'ş',
        'Ț' => 'ț',
        'Ţ' => 'ţ'
    ]);

    return strtolower($text);
}

function utf8_substr($text, $start, $length = null) {
    $text = (string) $text;
    $start = (int) $start;
    $length = $length !== null ? (int) $length : null;

    if (function_exists('mb_substr')) {
        return $length === null
            ? mb_substr($text, $start, null, 'UTF-8')
            : mb_substr($text, $start, $length, 'UTF-8');
    }

    if (!preg_match_all('/./us', $text, $matches)) {
        return '';
    }

    $characters = $matches[0];
    $characterCount = count($characters);

    if ($start < 0) {
        $start = max(0, $characterCount + $start);
    }

    if ($length === null) {
        $slice = array_slice($characters, $start);
    } else {
        $slice = array_slice($characters, $start, $length);
    }

    return implode('', $slice);
}

function normalize_search_text($text) {
    $text = utf8_strtolower($text);
    $text = strtr($text, [
        'ă' => 'a',
        'â' => 'a',
        'î' => 'i',
        'ș' => 's',
        'ş' => 's',
        'ț' => 't',
        'ţ' => 't'
    ]);
    $text = preg_replace('/[^a-z0-9 ]+/u', ' ', $text);
    $text = preg_replace('/\s+/u', ' ', trim($text));

    return $text;
}

function fuzzy_match_score($needle, $haystack) {
    $normalizedNeedle = normalize_search_text($needle);
    $normalizedHaystack = normalize_search_text($haystack);

    if ($normalizedNeedle === '' || $normalizedHaystack === '') {
        return null;
    }

    if (strpos($normalizedHaystack, $normalizedNeedle) !== false) {
        return 0;
    }

    $words = array_values(array_filter(explode(' ', $normalizedHaystack)));
    $candidates = $words;
    $candidates[] = $normalizedHaystack;

    $bestScore = null;
    foreach ($candidates as $candidate) {
        if ($candidate === '') {
            continue;
        }

        $distance = levenshtein($normalizedNeedle, $candidate);
        $maxDistance = max(1, (int) floor(max(strlen($normalizedNeedle), strlen($candidate)) / 3));

        similar_text($normalizedNeedle, $candidate, $similarity);
        $similarEnough = $similarity >= 72;

        if ($distance <= $maxDistance || $similarEnough) {
            if ($bestScore === null || $distance < $bestScore) {
                $bestScore = $distance;
            }
        }
    }

    return $bestScore;
}

function normalized_contains($needle, $haystack) {
    $normalizedNeedle = normalize_search_text($needle);
    $normalizedHaystack = normalize_search_text($haystack);

    if ($normalizedNeedle === '' || $normalizedHaystack === '') {
        return false;
    }

    return strpos($normalizedHaystack, $normalizedNeedle) !== false;
}

function get_did_you_mean($search, $matches) {
    $normalizedSearch = normalize_search_text($search);
    if ($normalizedSearch === '') {
        return null;
    }

    foreach ($matches as $match) {
        $productName = isset($match['productName']) ? $match['productName'] : '';
        if ($productName !== '' && normalized_contains($search, $productName)) {
            return null;
        }
    }

    $bestSuggestion = null;
    $bestScore = null;
    foreach ($matches as $match) {
        $productName = trim((string) (isset($match['productName']) ? $match['productName'] : ''));
        if ($productName === '') {
            continue;
        }

        $score = fuzzy_match_score($search, $productName);
        if ($score === null) {
            continue;
        }

        if (normalize_search_text($productName) === $normalizedSearch) {
            continue;
        }

        if ($bestScore === null || $score < $bestScore) {
            $bestScore = $score;
            $bestSuggestion = $productName;
        }
    }

    return $bestScore !== null && $bestScore <= max(2, (int) floor(strlen($normalizedSearch) / 3))
        ? $bestSuggestion
        : null;
}
?>
