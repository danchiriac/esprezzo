<?php
// Allow CORS for local web debugging - remove after development
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
// endpoints/products.php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../utils/helpers.php';

// Get userId if provided
$userId = isset($_GET['userId']) ? intval($_GET['userId']) : null;

if (isset($_GET['productId'])) {
    $productId = $_GET['productId'];
    // Get product details
    $stmt = $pdo->prepare('SELECT p.*, x.tags FROM products p LEFT JOIN (SELECT pt.IDProduct, GROUP_CONCAT(t.tag SEPARATOR \', \') as tags FROM productTags pt LEFT JOIN tags t ON t.ID = pt.IDTag AND t.IDSubcategory = 0 WHERE pt.IDProduct = ? GROUP BY pt.IDProduct) as x ON x.IDProduct = p.ID WHERE p.ID = ?');
    $stmt->execute([$productId, $productId]);
    $product = $stmt->fetch();
    if (!$product) {
        json_response(['error' => 'Product not found'], 404);
    }
    // Get all price tiers for this product, one row per store/enGros combination
    $pricesStmt = $pdo->prepare('SELECT p.ID as priceId, p.IDStore as storeId, s.location as store, p.price, p.enGros, p.date, p.inStock, pd.price as discountedPrice, pd.typeDiscount, IFNULL(pd.price, p.price) as actualPrice FROM prices as p INNER JOIN stores s ON s.ID = p.IDStore LEFT JOIN priceDiscounts as pd ON pd.IDPrice = p.ID AND pd.discountStartDate <= DATE(NOW()) AND pd.discountEndDate >= DATE(NOW()) WHERE p.IdProduct = ? ORDER BY s.location ASC, p.IDStore, p.enGros ASC, actualPrice ASC');
    $pricesStmt->execute([$productId]);
    $pricesArr = $pricesStmt->fetchAll();
    $prices = [];
    $favoriteStoreIds = [];
    $favoriteStoresMsg = '';
    $isFavoriteProduct = 0;
    if ($userId !== null && $userId > 0) {
        // Get favorite stores for user
        $favStmt = $pdo->prepare('SELECT IDStore FROM favoriteStores WHERE IDUser = ?');
        $favStmt->execute([$userId]);
        $favoriteStoreIds = array_column($favStmt->fetchAll(), 'IDStore');
    }
    if ($userId !== null && $userId > 0) {
        // Get favorite stores for user
        $favStmt = $pdo->prepare('SELECT 1 FROM favorites WHERE IDProduct = ? AND IDUser = ?');
        $favStmt->execute([$productId, $userId]);
        $isFavoriteProduct = $favStmt->fetchColumn() ? 1 : 0;
    }    
    $selectedStoreId = isset($_GET['storeId']) ? intval($_GET['storeId']) : 0;
    if ($userId !== null && $userId > 0 && count($favoriteStoreIds) > 0) {
        // Only show prices from favorite stores
        $pricesArr = array_values(array_filter($pricesArr, function ($price) use ($favoriteStoreIds, $selectedStoreId) {
            return in_array($price['storeId'], $favoriteStoreIds) ||
                ($selectedStoreId > 0 && intval($price['storeId']) === $selectedStoreId);
        }));
    } else if ($userId !== null && $userId > 0) {
        $favoriteStoresMsg = 'Puteti seta magazinele favorite daca va intereseaza doar anumite magazine';
    }

    foreach ($pricesArr as $price) {
        // Skip prices with value 0
        if ($price['price'] == 0 || $price['actualPrice'] == 0) {
            continue;
        }
        $prices[] = [
            'storeId' => $price['storeId'],
            'store' => $price['store'],
            'price' => $price['price'],
            'actualPrice' => $price['actualPrice'],
            'discountedPrice' => $price['discountedPrice'],
            'typeDiscount' => $price['typeDiscount'],
            'enGros' => $price['enGros'],
            'date' => $price['date'],
            'priceId' => $price['priceId'],
            'inStock' => $price['inStock']
        ];
    }
    // Get related products (same subcategory, excluding this product)
    $stmt = $pdo->prepare('SELECT p.ID, p.productName, p.photo, rp.relationType FROM products as p 
                            INNER JOIN relatedProducts as rp ON rp.IDProduct = p.ID 
                            INNER JOIN relatedProducts as rp2 ON rp.matchID = rp2.matchID AND rp.IDProduct != ? 
                            WHERE rp2.IDProduct=? ORDER BY rp2.matchID, rp2.relationType');
    $stmt->execute([$productId, $productId]);
    $related = $stmt->fetchAll();
    // Get all products in the same subcategory
    $stmt = $pdo->prepare('SELECT * FROM products WHERE IDSubCategory = ?');
    $stmt->execute([$product['IDSubCategory']]);
    $subcategoryProducts = $stmt->fetchAll();
    // Get subcategory and main category
    $stmt = $pdo->prepare('SELECT sc.ID as subcategoryId, sc.subcategory as subcategory, c.ID as categoryId, c.category as category FROM productSubCategories sc JOIN productCategories c ON sc.IDCategory = c.ID WHERE sc.ID = ?');
    $stmt->execute([$product['IDSubCategory']]);
    $cat = $stmt->fetch();
        json_response([
            'product' => $product,
            'userType' => get_user_type($pdo, $userId),
            'favorite' => $isFavoriteProduct,
            'prices' => $prices,
            'related' => $related,
            'subcategoryProducts' => $subcategoryProducts,
            'category' => $cat,
            'favoriteStoresMsg' => $favoriteStoresMsg
        ]);
} elseif (isset($_GET['barcode'])) {
    $barcode = $_GET['barcode'];
    $stmt = $pdo->prepare('SELECT * FROM products WHERE barcode = ?');
    $stmt->execute([$barcode]);
    $product = $stmt->fetch();
    $barcodeSearch = substr($barcode, 3, 5); // Get 5 characters starting from the 4th character (index 3)
    $barcodeSearch = '___'.$barcodeSearch.'%';
    $stmt = $pdo->prepare('SELECT distinct p.IDBrand FROM products p inner join brands b on b.ID = p.IDBrand where p.barcode like ?');
    $stmt->execute([$barcodeSearch]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($product) {
        json_response([
            'product' => $product
        ]);
    } else {
        json_response(['error' => 'Product not found', 
            'brandId' => intval($row['IDBrand'])], 404);
    }
} elseif (isset($_GET['search'])) {
    $rawSearch = trim((string) $_GET['search']);
    $normalizedSearch = normalize_search_text($rawSearch);
    $search = '%' . $rawSearch . '%';
    $normalizedLike = '%' . $normalizedSearch . '%';
    $userId = isset($_GET['userId']) ? intval($_GET['userId']) : null;
    $didYouMean = null;
    $normalizedProductNameSql = "LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(p.productName, ''), 'ă', 'a'), 'â', 'a'), 'î', 'i'), 'ș', 's'), 'ş', 's'), 'ț', 't'), 'ţ', 't'))";
    
    $stmt = $pdo->prepare("SELECT p.*, psc.subcategory, pc.category FROM products p INNER JOIN productSubCategories psc ON psc.ID = p.IDSubCategory INNER JOIN productCategories pc ON pc.ID = psc.IDCategory WHERE p.productName LIKE ? OR barcode LIKE ? OR $normalizedProductNameSql LIKE ?");
    $stmt->execute([$search, $search, $normalizedLike]);
    $productsArr = $stmt->fetchAll();

    if (strlen($rawSearch) >= 3 && count($productsArr) < 10) {
        $searchTokens = array_values(array_filter(explode(' ', $normalizedSearch)));
        $primaryToken = isset($searchTokens[0]) ? $searchTokens[0] : $normalizedSearch;
        $prefix2 = substr($primaryToken, 0, min(2, strlen($primaryToken)));
        $prefix3 = substr($primaryToken, 0, min(3, strlen($primaryToken)));
        $candidatePatterns = [];

        if ($prefix3 !== '') {
            $candidatePatterns[] = '%' . $prefix3 . '%';
        }
        if ($prefix2 !== '') {
            $candidatePatterns[] = '%' . $prefix2 . '%';
        }

        if (!empty($candidatePatterns)) {
            $candidateSql = 'SELECT p.*, psc.subcategory, pc.category FROM products p INNER JOIN productSubCategories psc ON psc.ID = p.IDSubCategory INNER JOIN productCategories pc ON pc.ID = psc.IDCategory WHERE';
            $candidateSql .= " $normalizedProductNameSql LIKE ?";
            $candidateParams = [$candidatePatterns[0]];

            if (isset($candidatePatterns[1])) {
                $candidateSql .= " OR $normalizedProductNameSql LIKE ?";
                $candidateParams[] = $candidatePatterns[1];
            }

            $candidateSql .= ' OR barcode LIKE ? LIMIT 250';
            $candidateParams[] = '%' . $rawSearch . '%';

            $candidateStmt = $pdo->prepare($candidateSql);
            $candidateStmt->execute($candidateParams);
            $candidateProducts = $candidateStmt->fetchAll();

            $existingIds = array_map(function ($product) {
                return (int) $product['ID'];
            }, $productsArr);

            $fuzzyMatches = [];
            foreach ($candidateProducts as $candidate) {
                $candidateId = (int) $candidate['ID'];
                if (in_array($candidateId, $existingIds, true)) {
                    continue;
                }

                $productNameValue = isset($candidate['productName']) ? $candidate['productName'] : '';
                $barcodeValue = isset($candidate['barcode']) ? $candidate['barcode'] : '';
                $nameScore = fuzzy_match_score($rawSearch, $productNameValue);
                $barcodeScore = fuzzy_match_score($rawSearch, $barcodeValue);

                $score = null;
                if ($nameScore !== null && $barcodeScore !== null) {
                    $score = min($nameScore, $barcodeScore);
                } elseif ($nameScore !== null) {
                    $score = $nameScore;
                } elseif ($barcodeScore !== null) {
                    $score = $barcodeScore;
                }

                if ($score !== null) {
                    $candidate['_fuzzyScore'] = $score;
                    $fuzzyMatches[] = $candidate;
                }
            }

            usort($fuzzyMatches, function ($a, $b) {
                $aProductName = isset($a['productName']) ? $a['productName'] : '';
                $bProductName = isset($b['productName']) ? $b['productName'] : '';

                if ($a['_fuzzyScore'] === $b['_fuzzyScore']) {
                    return strcmp($aProductName, $bProductName);
                }

                if ($a['_fuzzyScore'] < $b['_fuzzyScore']) {
                    return -1;
                }

                return 1;
            });

            $fuzzyMatches = array_slice($fuzzyMatches, 0, max(10, 20 - count($productsArr)));
            foreach ($fuzzyMatches as $candidate) {
                unset($candidate['_fuzzyScore']);
                $productsArr[] = $candidate;
            }
        }
    }

    if (strlen($rawSearch) >= 1) {
        $normalizedTagSql = "LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(t.tag, ''), 'ă', 'a'), 'â', 'a'), 'î', 'i'), 'ș', 's'), 'ş', 's'), 'ț', 't'), 'ţ', 't'))";
        $tagStmt = $pdo->prepare("SELECT DISTINCT t.ID, t.tag FROM tags t INNER JOIN productTags pt ON pt.IDTag = t.ID WHERE (t.tag LIKE ? OR $normalizedTagSql LIKE ?) ORDER BY t.tag ASC LIMIT 20");
        $tagStmt->execute([$search, $normalizedLike]);
        $tagRows = $tagStmt->fetchAll(PDO::FETCH_ASSOC);

        $existingTagIds = array_map(function ($product) {
            return isset($product['isTag']) && intval($product['isTag']) === 1 ? intval($product['tagId']) : 0;
        }, $productsArr);

        foreach ($tagRows as $tagRow) {
            $tagId = intval($tagRow['ID']);
            if (in_array($tagId, $existingTagIds, true)) {
                continue;
            }

            $productsArr[] = [
                'ID' => 0,
                'tagId' => $tagId,
                'isTag' => 1,
                'productName' => $tagRow['tag'],
                'photo' => null,
                'category' => 'Tag',
                'subcategory' => 'Tag',
                'favorite' => 0,
            ];
        }
    }

    $didYouMean = get_did_you_mean($rawSearch, $productsArr);
    
    // Add favorite status if userId is provided
    $products = [];
    if ($userId !== null && $userId > 0) {
        foreach ($productsArr as $product) {
            $favStmt = $pdo->prepare('SELECT 1 FROM favorites WHERE IDProduct = ? AND IDUser = ?');
            $favStmt->execute([$product['ID'], $userId]);
            $isFavorite = $favStmt->fetchColumn() ? 1 : 0;
            $product['favorite'] = $isFavorite;
            $products[] = $product;
        }
    } else {
        foreach ($productsArr as $product) {
            $product['favorite'] = 0;
            $products[] = $product;
        }
    }

    if ($rawSearch !== '') {
        try {
            $matchedProductId = 0;
            $productMatches = array_values(array_filter($productsArr, function ($product) {
                return isset($product['ID']) && intval($product['ID']) > 0 && (!isset($product['isTag']) || intval($product['isTag']) !== 1);
            }));

            if (count($productMatches) === 1) {
                $matchedProductId = (int) $productMatches[0]['ID'];
            }

            $historyStmt = $pdo->prepare('INSERT INTO searchHistory (`search`, `IDUser`, `IDProduct`, `noResults`) VALUES (?, ?, ?, ?)');
            $historyStmt->execute([
                utf8_substr($rawSearch, 0, 50),
                isset($userId) ? $userId : 0,
                $matchedProductId,
                empty($products) ? 1 : 0
            ]);
        } catch (PDOException $e) {
            error_log('Failed to save product search history: ' . $e->getMessage());
        }
    }
    
    $barcodeSearch = substr($_GET['search'], 3, 5);
    $barcodeSearch = '___'.$barcodeSearch.'%';    
    $stmt = $pdo->prepare('SELECT distinct p.IDBrand FROM products p inner join brands b on b.ID = p.IDBrand where p.barcode like ?');
    $stmt->execute([$barcodeSearch]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    json_response(['products' => $products, 
            'brandId' => intval($row['IDBrand']),
            'didYouMean' => $didYouMean]);
} else {
    json_response(['error' => 'Invalid request'], 400);
}
?>
