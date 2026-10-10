<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Adauga Produs Nou</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        form { max-width: 500px; margin: auto; }
        label { display: block; margin-top: 16px; font-weight: bold; }
        input, select { width: 100%; padding: 8px; margin-top: 4px; }
        button { margin-top: 24px; padding: 10px 20px; font-size: 16px; }
        .error { color: red; margin-top: 12px; }
        .success { color: green; margin-top: 12px; }
    </style>
</head>
<body>
    <h2>Adauga Produs Nou</h2>
    <form id="addProductForm">
        <label for="barcode">Cod Bare</label>
        <input type="text" id="barcode" name="barcode" required>

        <label for="productName">Nume Produs</label>
        <input type="text" id="productName" name="productName" required>

        <label for="brandId">Brand</label>
        <select id="brandId" name="brandId" required></select>

        <label for="mainCategoryId">Categorie Principala</label>
        <select id="mainCategoryId" name="mainCategoryId" required></select>

        <label for="categoryId">Categorie</label>
        <select id="categoryId" name="categoryId" required></select>

        <label for="subcategoryId">Subcategorie</label>
        <select id="subcategoryId" name="subcategoryId" required></select>

        <label for="quantity">Cantitate</label>
        <input type="number" id="quantity" name="quantity">

        <label for="quantityType">Tip Cantitate</label>
        <select id="quantityType" name="quantityType">  
            <option value="1">grams</option>
            <option value="2">kilograms</option>
            <option value="3">mililiters</option>
            <option value="4">liters</option>
            <option value="5">items</option>
        </select>

        <label for="weightUnit">Greutate pe bucata</label>
        <input type="number" id="weightUnit" name="weightUnit">

        <label for="weightTotal">Greutate Totala</label>
        <input type="number" id="weightTotal" name="weightTotal">

        <button type="submit">Adauga Produs</button>
        <div id="result"></div>
    </form>

    <script>
    let currentUser = null;
    async function loadCurrentUser() {
        const userId = localStorage.getItem('userId');
        const authToken = localStorage.getItem('authToken');
        if (!userId || !authToken) return null;
        const resp = await fetch('https://esprezzo.clusium.ro/api/endpoints/get_user_type.php?userId=' + encodeURIComponent(userId));
        const data = await resp.json();
        if (!data.success) return null;
        const userType = Number(data.userType) || 0;
        localStorage.setItem('userType', String(userType));
        return { userId, authToken, userType };
    }

    // Helper to fetch and populate select options
    async function populateSelect(url, selectId, valueKey, textKey) {
        const resp = await fetch(url);
        const data = await resp.json();
        const select = document.getElementById(selectId);
        select.innerHTML = '';
        let arr = data[Object.keys(data)[0]];
        arr.forEach(item => {
            const opt = document.createElement('option');
            opt.value = item[valueKey];
            opt.textContent = item[textKey];
            select.appendChild(opt);
        });
    }

    // Populate brands and main categories on load
    window.onload = async function() {
        currentUser = await loadCurrentUser();
        if (!currentUser || currentUser.userType < 2) {
            document.getElementById('addProductForm').hidden = true;
            document.getElementById('result').textContent = 'Autentificare necesara. Doar rolurile 2 si 3 pot adauga produse.';
            document.getElementById('result').className = 'error';
            return;
        }
        await populateSelect('https://esprezzo.clusium.ro/api/endpoints/get_brands.php', 'brandId', 'ID', 'brand');
        await populateSelect('https://esprezzo.clusium.ro/api/endpoints/get_main_categories.php', 'mainCategoryId', 'ID', 'mainCategory');
        // Trigger category population
        document.getElementById('mainCategoryId').dispatchEvent(new Event('change'));
    };

    // Populate categories when main category changes
    document.getElementById('mainCategoryId').addEventListener('change', async function() {
        const mainCategoryId = this.value;
        await populateSelect('https://esprezzo.clusium.ro/api/endpoints/get_categories.php?mainCategoryId=' + mainCategoryId, 'categoryId', 'ID', 'category');
        document.getElementById('categoryId').dispatchEvent(new Event('change'));
    });

    // Populate subcategories when category changes
    document.getElementById('categoryId').addEventListener('change', async function() {
        const categoryId = this.value;
        await populateSelect('https://esprezzo.clusium.ro/api/endpoints/get_subcategories.php?categoryId=' + categoryId, 'subcategoryId', 'ID', 'subcategory');
    });

    // Handle form submission
    document.getElementById('addProductForm').onsubmit = async function(e) {
        e.preventDefault();
        const resultDiv = document.getElementById('result');
        resultDiv.textContent = '';
        const formData = {
            userId: currentUser.userId,
            authToken: currentUser.authToken,
            barcode: document.getElementById('barcode').value,
            productName: document.getElementById('productName').value,
            brandId: document.getElementById('brandId').value,
            subcategoryId: document.getElementById('subcategoryId').value,
            quantity: document.getElementById('quantity').value,
            quantityType: document.getElementById('quantityType').value,
            weightUnit: document.getElementById('weightUnit').value,
            weightTotal: document.getElementById('weightTotal').value
        };
        const resp = await fetch('https://esprezzo.clusium.ro/api/endpoints/add_product.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(formData)
        });
        const data = await resp.json();
        if (data.success) {
            resultDiv.textContent = 'Produs adaugat cu succes!';
            resultDiv.className = 'success';
            document.getElementById('addProductForm').reset();
        } else {
            resultDiv.textContent = 'Eroare: ' + (data.error || 'necunoscuta') + '\n' + JSON.stringify(data);
            resultDiv.className = 'error';
        }
    };
    </script>
</body>
</html>
