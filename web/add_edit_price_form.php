<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Adauga/Editeaza Pret Produs</title>
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
    <h2>Adauga/Editeaza Pret Produs</h2>
    <form id="priceForm">
        <label for="productId">Produs</label>
        <select id="productId" name="productId" required></select>

        <label for="storeId">Magazin</label>
        <select id="storeId" name="storeId" required></select>

        <label for="price">Pret (lei)</label>
        <input type="number" id="price" name="price" step="0.01" required>

        <label for="enGros">EnGros (bucati)</label>
        <input type="number" id="enGros" name="enGros" value="1" required>

        <button type="submit">Salveaza Pret</button>
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

    // Populate products
    async function populateProducts() {
        const resp = await fetch('https://esprezzo.clusium.ro/api/endpoints/products.php?search=');
        const data = await resp.json();
        const select = document.getElementById('productId');
        select.innerHTML = '';
        (data.products || []).forEach(prod => {
            const opt = document.createElement('option');
            opt.value = prod.ID;
            opt.textContent = prod.productName + ' [' + prod.barcode + ']';
            select.appendChild(opt);
        });
    }
    // Populate stores
    async function populateStores() {
        const resp = await fetch('https://esprezzo.clusium.ro/api/endpoints/products.php?productId=' + document.getElementById('productId').value);
        const data = await resp.json();
        const select = document.getElementById('storeId');
        select.innerHTML = '';
        (data.prices || []).forEach(store => {
            const opt = document.createElement('option');
            opt.value = store.storeId;
            opt.textContent = store.store + (store.price !== null ? ' (pret: ' + store.price + ' lei)' : ' (fara pret)');
            select.appendChild(opt);
        });
        // If a price exists, prefill fields
        const selectedStore = data.prices.find(s => s.storeId == select.value);
        if (selectedStore && selectedStore.price !== null) {
            document.getElementById('price').value = selectedStore.price;
            document.getElementById('enGros').value = selectedStore.enGros;
        } else {
            document.getElementById('price').value = '';
            document.getElementById('enGros').value = 1;
        }
    }
    document.getElementById('productId').addEventListener('change', populateStores);
    document.getElementById('storeId').addEventListener('change', populateStores);
    window.onload = async function() {
        currentUser = await loadCurrentUser();
        if (!currentUser || currentUser.userType < 1) {
            document.getElementById('priceForm').hidden = true;
            document.getElementById('result').textContent = 'Autentificare necesara. Rolurile 1, 2 sau 3 pot edita preturile.';
            document.getElementById('result').className = 'error';
            return;
        }
        await populateProducts();
        await populateStores();
    };
    document.getElementById('priceForm').onsubmit = async function(e) {
        e.preventDefault();
        const resultDiv = document.getElementById('result');
        resultDiv.textContent = '';
        const formData = {
            userId: currentUser.userId,
            authToken: currentUser.authToken,
            productId: document.getElementById('productId').value,
            storeId: document.getElementById('storeId').value,
            price: document.getElementById('price').value,
            enGros: document.getElementById('enGros').value
        };
        const resp = await fetch('https://esprezzo.clusium.ro/api/endpoints/add_or_update_price.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(formData)
        });
        const data = await resp.json();
        if (data.success) {
            resultDiv.textContent = 'Pret salvat cu succes!';
            resultDiv.className = 'success';
            await populateStores();
        } else {
            resultDiv.textContent = 'Eroare: ' + (data.error || 'necunoscuta') + '\n' + JSON.stringify(data);
            resultDiv.className = 'error';
        }
    };
    </script>
</body>
</html>
