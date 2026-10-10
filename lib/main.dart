import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SplashApp());
}

class SplashApp extends StatelessWidget {
  const SplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Esprezzo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ProductSearchApp()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset('assets/logo_splash.png', width: 300, height: 150),
      ),
    );
  }
}

class ProductSearchApp extends StatelessWidget {
  const ProductSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cautare produse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const ProductSearchPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ProductSearchPage extends StatefulWidget {
  final bool openScannerOnStart;
  final bool openAccountOnStart;

  const ProductSearchPage({
    super.key,
    this.openScannerOnStart = false,
    this.openAccountOnStart = false,
  });

  @override
  State<ProductSearchPage> createState() => _ProductSearchPageState();
}

class _ProductSearchPageState extends State<ProductSearchPage> {
  String? _username;
  String? _userId;
  String? _authToken;
  int _userType = 0;
  String _appVersion = '';
  List<dynamic> _stores = [];
  int? _selectedStoreId;
  int _gpsStoreId = 0;

  // Product search related fields
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _products = [];
  bool _loading = false;
  String? _error;
  String? _didYouMean;
  int _brandId = 0;

  // Form field variables
  int? brandId;
  int? mainCategoryId;
  int? categoryId;
  int? subcategoryId;
  final List<dynamic> _brands = [];
  final List<dynamic> _mainCategories = [];
  final List<dynamic> _categories = [];
  final List<dynamic> _subcategories = [];

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _restoreUser();
    _detectAndSelectNearbyStore();
    _restoreSelectedStore();
    _fetchStores();
  }

  Future<void> _restoreUser() async {
    // Restore user from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final userId = prefs.getString('userId');
    final authToken = prefs.getString('authToken');
    if (username != null && userId != null && userId.isNotEmpty) {
      var userType = prefs.getInt('userType') ?? 0;
      try {
        final response = await http.get(
          Uri.parse(
            'https://esprezzo.clusium.ro/api/endpoints/get_user_type.php?userId=${Uri.encodeComponent(userId)}',
          ),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          userType = int.tryParse(data['userType']?.toString() ?? '') ?? 0;
          await prefs.setInt('userType', userType);
        }
      } catch (e) {
        debugPrint('Could not refresh user type: $e');
      }
      setState(() {
        _username = username;
        _userId = userId;
        _authToken = authToken;
        _userType = userType;
      });
    }
    if (mounted && widget.openAccountOnStart) {
      await _showLoginDialog();
    } else if (mounted && widget.openScannerOnStart) {
      await _scanBarcode();
    }
  }

  Future<void> _restoreSelectedStore() async {
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getInt('selectedStoreId');
    if (storeId != null && storeId != 0) {
      setState(() {
        if (_gpsStoreId > 0) {
          _selectedStoreId = _gpsStoreId;
        } else {
          _selectedStoreId = storeId;
        }
        debugPrint('Restored selectedStoreId: $_selectedStoreId');
      });
    }
  }

  Future<void> _detectAndSelectNearbyStore() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _showLocationServiceDialog();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _showLocationPermissionDialog();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        await _showLocationPermissionDialog(permanentlyDenied: true);
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      double latitude = position.latitude;
      double longitude = position.longitude;
      // Call your API to check for nearby stores (within 200m)
      await _checkNearbyStore(latitude, longitude);
    } catch (e) {
      // Optionally handle error
    }
  }

  Future<void> _checkNearbyStore(double latitude, double longitude) async {
    final url =
        'https://esprezzo.clusium.ro/api/endpoints/check_nearby_store.php?lat=$latitude&lng=$longitude&radius=200';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      final storeId = int.tryParse(data['storeId']?.toString() ?? '0') ?? 0;
      if (storeId == 0 || !mounted) return;

      setState(() {
        _gpsStoreId = storeId;
        _selectedStoreId = storeId;
      });
    } catch (e) {
      debugPrint('Could not detect nearby store: $e');
    }
  }

  Future<void> _showLocationServiceDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Serviciul de localizare este dezactivat'),
        content: const Text(
          'Activează serviciile de localizare pentru a detecta magazine apropiate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationPermissionDialog({
    bool permanentlyDenied = false,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisiune locație necesară'),
        content: Text(
          permanentlyDenied
              ? 'Permisiunea de locație a fost refuzată permanent. Deschide setările aplicației pentru a permite accesul la locație.'
              : 'Permisiunea de locație este necesară pentru a detecta magazine apropiate.',
        ),
        actions: [
          if (permanentlyDenied)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await Geolocator.openAppSettings();
              },
              child: const Text('Deschide setări'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = info.version;
    });
  }

  Future<void> _showLoginDialog() async {
    if (_username != null && _username!.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AccountPage(
            userId: _userId!,
            username: _username!,
            appVersion: _appVersion,
            userType: _userType,
          ),
        ),
      );
      return;
    }

    String username = '';
    String password = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autentificare'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Utilizator'),
              onChanged: (value) => username = value,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Parola'),
              obscureText: true,
              onChanged: (value) => password = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () async {
              final response = await http.post(
                Uri.parse('https://esprezzo.clusium.ro/api/endpoints/auth.php'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({'email': username, 'password': password}),
              );
              final responseData = json.decode(response.body);
              if (response.statusCode == 200 &&
                  responseData['success'] == true) {
                setState(() {
                  _username = username;
                  _userId = responseData['userId']?.toString();
                  _authToken = responseData['authToken']?.toString();
                  _userType =
                      int.tryParse(responseData['userType']?.toString() ?? '') ??
                      0;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('username', username);
                await prefs.setString('userId', _userId ?? '');
                await prefs.setString('authToken', _authToken ?? '');
                await prefs.setInt('userType', _userType);
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Autentificare reușită!')),
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const ProductSearchPage(),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Autentificare eșuată: ${responseData['error'] ?? 'Eroare necunoscută'}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Autentificare'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProductForm(String barcode, int brId) async {
    if (_userType < 2 || _authToken == null || _authToken!.isEmpty) return;
    String productName = '';
    int? brandId = brId != 0 ? brId : null;
    int? mainCategoryId;
    int? categoryId;
    int? subcategoryId;
    String quantity = '';
    String quantityType = 'bucati';
    final List<String> quantityTypes = [
      'grame',
      'kilograme',
      'mililitri',
      'litri',
      'bucati',
    ];
    String weightUnit = '';
    String weightTotal = '';

    List<dynamic> brands = [];
    List<dynamic> mainCategories = [];
    List<dynamic> categories = [];
    List<dynamic> subcategories = [];

    // Fetch brands
    final brandsResp = await http.get(
      Uri.parse('https://esprezzo.clusium.ro/api/endpoints/get_brands.php'),
    );
    if (brandsResp.statusCode == 200) {
      brands = json.decode(brandsResp.body)['brands'] ?? [];
      // Validate brandId against fetched brands
      if (brandId != null) {
        final found = brands.any(
          (b) => int.tryParse(b['ID'].toString()) == brandId,
        );
        if (!found) brandId = null;
      }
    }
    // Fetch main categories
    final mainCatResp = await http.get(
      Uri.parse(
        'https://esprezzo.clusium.ro/api/endpoints/get_main_categories.php',
      ),
    );
    if (mainCatResp.statusCode == 200) {
      mainCategories = json.decode(mainCatResp.body)['mainCategories'] ?? [];
    }
    // Helper to fetch and preselect categories/subcategories
    Future<void> fetchBrandCategories(
      int brandId,
      void Function(void Function()) setState,
    ) async {
      final resp = await http.get(
        Uri.parse(
          'https://esprezzo.clusium.ro/api/endpoints/get_brand_categories.php?brandId=$brandId',
        ),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final mainCatId =
            int.tryParse(data['IDMainCategory']?.toString() ?? '0') ?? 0;
        final catId = int.tryParse(data['IDCategory']?.toString() ?? '0') ?? 0;
        final subcatId =
            int.tryParse(data['IDSubCategory']?.toString() ?? '0') ?? 0;
        if (mainCatId != 0) {
          // Fetch categories for mainCatId
          final catResp = await http.get(
            Uri.parse(
              'https://esprezzo.clusium.ro/api/endpoints/get_categories.php?mainCategoryId=$mainCatId',
            ),
          );
          List<dynamic> cats = [];
          if (catResp.statusCode == 200) {
            cats = json.decode(catResp.body)['categories'] ?? [];
          }
          // Fetch subcategories for catId
          List<dynamic> subcats = [];
          if (catId != 0) {
            final subcatResp = await http.get(
              Uri.parse(
                'https://esprezzo.clusium.ro/api/endpoints/get_subcategories.php?categoryId=$catId',
              ),
            );
            if (subcatResp.statusCode == 200) {
              subcats = json.decode(subcatResp.body)['subcategories'] ?? [];
            }
          }
          setState(() {
            mainCategoryId = mainCatId;
            categories = cats;
            categoryId = catId != 0 ? catId : null;
            subcategories = subcats;
            subcategoryId = subcatId != 0 ? subcatId : null;
          });
        }
      }
    }

    // If brandId is pre-selected, fetch brand categories before showing dialog
    if (brandId != null) {
      // Use a dummy setState to update local variables before dialog
      await fetchBrandCategories(brandId, (fn) => fn());
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Adauga produs nou'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cod bare:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(barcode, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Nume produs',
                      ),
                      onChanged: (v) => productName = v,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Brand'),
                      initialValue: brandId,
                      items: brands
                          .map<DropdownMenuItem<int>>(
                            (b) => DropdownMenuItem(
                              value: int.tryParse(b['ID'].toString()),
                              child: Text(b['brand']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) async {
                        setState(() {
                          brandId = v;
                          mainCategoryId = null;
                          categoryId = null;
                          subcategoryId = null;
                          categories = [];
                          subcategories = [];
                        });
                        if (v != null) {
                          await fetchBrandCategories(v, setState);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Categorie principala',
                      ),
                      initialValue: mainCategoryId,
                      items: mainCategories
                          .map<DropdownMenuItem<int>>(
                            (c) => DropdownMenuItem(
                              value: int.tryParse(c['ID'].toString()),
                              child: Text(c['mainCategory']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) async {
                        setState(() {
                          mainCategoryId = v;
                          categoryId = null;
                          subcategoryId = null;
                          categories = [];
                          subcategories = [];
                        });
                        // Fetch categories
                        final catResp = await http.get(
                          Uri.parse(
                            'https://esprezzo.clusium.ro/api/endpoints/get_categories.php?mainCategoryId=$v',
                          ),
                        );
                        if (catResp.statusCode == 200) {
                          setState(() {
                            categories =
                                json.decode(catResp.body)['categories'] ?? [];
                          });
                        }
                      },
                    ),
                    if (mainCategoryId != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Categorie',
                        ),
                        initialValue: categoryId,
                        items: categories
                            .map<DropdownMenuItem<int>>(
                              (c) => DropdownMenuItem(
                                value: int.tryParse(c['ID'].toString()),
                                child: Text(c['category']),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          setState(() {
                            categoryId = v;
                            subcategoryId = null;
                            subcategories = [];
                          });
                          // Fetch subcategories
                          final subcatResp = await http.get(
                            Uri.parse(
                              'https://esprezzo.clusium.ro/api/endpoints/get_subcategories.php?categoryId=$v',
                            ),
                          );
                          if (subcatResp.statusCode == 200) {
                            setState(() {
                              subcategories =
                                  json.decode(
                                    subcatResp.body,
                                  )['subcategories'] ??
                                  [];
                            });
                          }
                        },
                      ),
                    ],
                    if (categoryId != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Subcategorie',
                        ),
                        initialValue: subcategoryId,
                        items: subcategories
                            .map<DropdownMenuItem<int>>(
                              (s) => DropdownMenuItem(
                                value: int.tryParse(s['ID'].toString()),
                                child: Text(s['subcategory']),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => subcategoryId = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Cantitate'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => quantity = v,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Tip cantitate',
                      ),
                      initialValue: quantityType,
                      items: quantityTypes
                          .map(
                            (qt) =>
                                DropdownMenuItem(value: qt, child: Text(qt)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => quantityType = v ?? 'bucati'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Greutate pe bucata (daca e cazul)',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => weightUnit = v,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Greutate totala',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => weightTotal = v,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Renunta'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (productName.isEmpty ||
                        brandId == null ||
                        subcategoryId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Completeaza toate campurile obligatorii!',
                          ),
                        ),
                      );
                      return;
                    }
                    // Map quantityType string to index (1-based)
                    int quantityTypeIndex =
                        quantityTypes.indexOf(quantityType) + 1;
                    final resp = await http.post(
                      Uri.parse(
                        'https://esprezzo.clusium.ro/api/endpoints/add_product.php',
                      ),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'userId': _userId,
                        'authToken': _authToken,
                        'barcode': barcode,
                        'productName': productName,
                        'brandId': brandId,
                        'subcategoryId': subcategoryId,
                        'quantity': quantity,
                        'quantityType': quantityTypeIndex,
                        'weightUnit': weightUnit,
                        'weightTotal': weightTotal,
                      }),
                    );
                    final respBody = resp.body;
                    final respJson = json.decode(respBody);
                    if (resp.statusCode == 200 && respJson['success'] == true) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Produs adaugat cu succes!'),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Eroare la adaugare produs: ${respJson['error'] ?? 'necunoscuta'}\nRaspuns complet: $respBody',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Adauga produs'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _searchProducts(String query) async {
    setState(() {
      _loading = true;
      _error = null;
      _didYouMean = null;
      _products = [];
      _brandId = 0;
    });
    try {
      final response = await http.get(
        Uri.parse(
          'https://esprezzo.clusium.ro/api/endpoints/products.php?search=${Uri.encodeComponent(query)}${_selectedStoreId != null ? '&storeId=$_selectedStoreId' : ''}${_userId != null && _userId!.isNotEmpty ? '&userId=${Uri.encodeComponent(_userId!)}' : ''}',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _products = data['products'] ?? [];
          _didYouMean = data['didYouMean']?.toString();
          _brandId = data['brandId'] ?? 0;
        });
        // If barcode search and no products found, show add product form
        if (_userType >= 2 &&
            _authToken != null &&
            _authToken!.isNotEmpty &&
            _products.isEmpty &&
            query.length >= 8 &&
            int.tryParse(query) != null) {
          await _showAddProductForm(query, _brandId);
        }
      } else {
        setState(() {
          _error = 'Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to connect to API';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _openProductDetails(dynamic product) async {
    final productId = product['ID'] ?? product['ID'];
    if (productId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProductDetailsPage(
            productId: int.tryParse(productId.toString()) ?? 0,
            userId: _userId,
            storeId: _selectedStoreId,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product ID ${productId ?? 'unknown'} not found.'),
        ),
      );
    }
  }

  Future<void> _addToShoppingList(dynamic product) async {
    if (_userId == null || _userId!.isEmpty) return;
    final isTag = product['isTag'] == 1 || product['isTag'] == true;
    final productId = isTag
        ? 0
        : int.tryParse(product['ID']?.toString() ?? '0') ?? 0;
    final tagId = isTag
        ? int.tryParse(product['tagId']?.toString() ?? '0') ?? 0
        : 0;
    if (!isTag && productId <= 0) return;
    if (isTag && tagId <= 0) return;
    final url =
        'https://esprezzo.clusium.ro/api/endpoints/add_to_shopping_list.php';
    final body = json.encode({
      'userId': _userId,
      'productId': productId,
      'tagId': tagId,
      'storeId': _selectedStoreId ?? 0,
      'listName': 'Lista cumparaturi',
    });
    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      final respJson = json.decode(resp.body);
      if (resp.statusCode == 200 && respJson['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produs adaugat la lista!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Eroare la adaugare: ${respJson['error'] ?? 'necunoscuta'}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exceptie la adaugare: $e')));
    }
  }

  Future<void> _scanBarcode() async {
    String? scannedBarcode;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Scan Barcode'),
          content: SizedBox(
            width: 300,
            height: 300,
            child: MobileScanner(
              onDetect: (barcodeCapture) {
                final barcode = barcodeCapture.barcodes.first;
                if (barcode.rawValue != null) {
                  scannedBarcode = barcode.rawValue;
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
        );
      },
    );
    if (scannedBarcode != null && scannedBarcode!.isNotEmpty) {
      _controller.text = scannedBarcode!;
      await _searchProducts(scannedBarcode!);
    }
  }

  Future<void> _toggleFavorite(dynamic product) async {
    if (_userId == null || _userId!.isEmpty) return;
    final productId = product['ID']?.toString();
    if (productId == null) return;
    final isCurrentlyFavorite = product['favorite'] == 1;
    final url = isCurrentlyFavorite
        ? 'https://esprezzo.clusium.ro/api/endpoints/remove_favorite.php'
        : 'https://esprezzo.clusium.ro/api/endpoints/add_favorite.php';
    final body = json.encode({'userId': _userId, 'productId': productId});
    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      final respJson = json.decode(resp.body);
      if (resp.statusCode == 200 && respJson['success'] == true) {
        setState(() {
          product['favorite'] = isCurrentlyFavorite ? 0 : 1;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Eroare la actualizare favorite: '
              '${respJson['error'] ?? 'necunoscuta'}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exceptie la favorite: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cauta Produs')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Store select box
            if (_stores.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Selecteaza magazin',
                  ),
                  initialValue: _selectedStoreId,
                  items: _stores
                      .map<DropdownMenuItem<int>>(
                        (s) => DropdownMenuItem(
                          value: int.tryParse(s['ID'].toString()),
                          child: Text(s['location']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedStoreId = v;
                    });
                  },
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText:
                          'Cauta produs, brand sau cod bare (ultimele 4 cifre)',
                    ),
                    onSubmitted: _searchProducts,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Sterge cautarea',
                  onPressed: () {
                    setState(() {
                      _controller.clear();
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Cauta produs',
                  onPressed: () => _searchProducts(_controller.text),
                ),
              ],
            ),
            // Barcode scan button under the search input
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: IconButton(
                  icon: const Icon(Icons.qr_code),
                  tooltip: 'Scanare cod bare',
                  onPressed: _scanBarcode,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (!_loading &&
                _didYouMean != null &&
                _didYouMean!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      const Text('Ai vrut sa cauti:'),
                      ActionChip(
                        label: Text(_didYouMean!),
                        onPressed: () {
                          _controller.text = _didYouMean!;
                          _searchProducts(_didYouMean!);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loading && _products.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final isTag =
                        product['isTag'] == 1 || product['isTag'] == true;
                    String photoUrl =
                        'https://www.clusium.ro/photos/${product['photo']?.toString() ?? 'no-image.png'}';
                    return Card(
                      child: ListTile(
                        leading:
                            !isTag &&
                                product['photo'] != null &&
                                product['photo'].toString().isNotEmpty
                            ? Image.network(
                                photoUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.sell_outlined),
                        title: Text(product['productName'] ?? 'No name'),
                        subtitle: Text(
                          isTag
                              ? 'Tag general'
                              : '${product['category'] ?? '-'} > ${product['subcategory'] ?? '-'}',
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_userId != null && _userId!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.shopping_cart),
                                tooltip: 'Adauga la lista',
                                onPressed: () => _addToShoppingList(product),
                              ),
                            if (!isTag &&
                                _userId != null &&
                                _userId!.isNotEmpty)
                              IconButton(
                                icon: Icon(
                                  (product['favorite'] == 1)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: (product['favorite'] == 1)
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                                tooltip: (product['favorite'] == 1)
                                    ? 'Elimina din favorite'
                                    : 'Adauga la favorite',
                                onPressed: () async {
                                  await _toggleFavorite(product);
                                },
                              ),
                          ],
                        ),
                        onTap: () => isTag
                            ? _addToShoppingList(product)
                            : _openProductDetails(product),
                      ),
                    );
                  },
                ),
              ),
            if (!_loading && _products.isEmpty && _error == null)
              Expanded(child: Center(child: Text('No products found.'))),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        userId: _userId,
        userType: _userType,
        storeId: _selectedStoreId,
        onScan: _scanBarcode,
        onAccount: _showLoginDialog,
      ),
    );
  }

  Future<void> _fetchStores() async {
    String url = 'https://esprezzo.clusium.ro/api/endpoints/get_stores.php';
    if (_userId != null && _userId!.isNotEmpty) {
      url += '?userId=${Uri.encodeComponent(_userId!)}';
    }
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        setState(() {
          _stores = data['stores'] ?? [];
        });
      }
    } catch (e) {
      // Optionally handle error
    }
  }
}

// Move ProductDetailsPage and _ProductDetailsPageState to top-level

class AppBottomNavigationBar extends StatelessWidget {
  final String? userId;
  final int userType;
  final int? storeId;
  final VoidCallback? onScan;
  final VoidCallback? onAccount;

  const AppBottomNavigationBar({
    super.key,
    this.userId,
    this.userType = 0,
    this.storeId,
    this.onScan,
    this.onAccount,
  });

  void _openHome(BuildContext context, {bool scan = false, bool account = false}) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => ProductSearchPage(
          openScannerOnStart: scan,
          openAccountOnStart: account,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (userType >= 2)
            IconButton(
              tooltip: 'Update',
              icon: const Icon(Icons.system_update_alt),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Actiunea Update va fi definita ulterior.'),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'Scanare cod bare',
            icon: const Icon(Icons.qr_code),
            onPressed: onScan ?? () => _openHome(context, scan: true),
          ),
          IconButton(
            tooltip: 'Promotii',
            icon: const Icon(Icons.percent),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => PromotionsPage(
                    userId: userId,
                    userType: userType,
                    storeId: storeId,
                  ),
                ),
                (route) => false,
              );
            },
          ),
          IconButton(
            tooltip: 'Cautare produse',
            icon: const Icon(Icons.search),
            onPressed: () => _openHome(context),
          ),
          IconButton(
            tooltip: 'Lista cumparaturi',
            icon: const Icon(Icons.shopping_cart),
            onPressed: userId == null || userId!.isEmpty
                ? null
                : () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => ShoppingListPage(
                          userId: userId!,
                          userType: userType,
                        ),
                      ),
                      (route) => false,
                    );
                  },
          ),
          IconButton(
            tooltip: 'Contul meu',
            icon: const Icon(Icons.person),
            onPressed: onAccount ?? () => _openHome(context, account: true),
          ),
        ],
      ),
    );
  }
}

class PromotionsPage extends StatefulWidget {
  final String? userId;
  final int userType;
  final int? storeId;

  const PromotionsPage({
    super.key,
    this.userId,
    this.userType = 0,
    this.storeId,
  });

  @override
  State<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends State<PromotionsPage> {
  List<dynamic> _promotions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPromotions();
  }

  Future<void> _loadPromotions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse(
          'https://esprezzo.clusium.ro/api/endpoints/get_promotions.php',
        ),
      );
      final data = json.decode(response.body);
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Nu s-au putut incarca promotiile.');
      }
      if (!mounted) return;
      setState(() {
        _promotions = data['promotions'] ?? [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Nu s-au putut incarca promotiile. Verifica conexiunea.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openPromotion(dynamic promotion) {
    final productId = int.tryParse(promotion['productId']?.toString() ?? '');
    if (productId == null) return;
    final storeId = int.tryParse(promotion['storeId']?.toString() ?? '');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductDetailsPage(
          productId: productId,
          userId: widget.userId,
          storeId: storeId ?? widget.storeId,
        ),
      ),
    );
  }

  Widget _buildPromotionTile(dynamic promotion) {
    final productName = promotion['productName']?.toString() ?? 'Produs';
    final photo = promotion['photo']?.toString() ?? '';
    final store = promotion['store']?.toString() ?? '-';
    final originalPrice =
        double.tryParse(promotion['originalPrice']?.toString() ?? '') ?? 0;
    final promoPrice =
        double.tryParse(promotion['promoPrice']?.toString() ?? '') ?? 0;
    final savings = originalPrice - promoPrice;
    final endDate = promotion['endDate']?.toString() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPromotion(promotion),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 76,
                child: photo.isEmpty
                    ? const Icon(Icons.image_not_supported_outlined, size: 40)
                    : Image.network(
                        'https://www.clusium.ro/photos/$photo',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.image_not_supported_outlined,
                              size: 40,
                            ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(store, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (savings > 0)
                      Text(
                        'Economisesti ${savings.toStringAsFixed(2)} lei',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    if (endDate.isNotEmpty)
                      Text(
                        'Valabila pana la ${endDate.split(' ').first}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${promoPrice.toStringAsFixed(2)} lei',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${originalPrice.toStringAsFixed(2)} lei',
                    style: const TextStyle(
                      color: Colors.black54,
                      decoration: TextDecoration.lineThrough,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotii active'),
        actions: [
          IconButton(
            tooltip: 'Reincarca promotiile',
            onPressed: _loading ? null : _loadPromotions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadPromotions,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Incearca din nou'),
                  ),
                ],
              ),
            )
          : _promotions.isEmpty
          ? const Center(child: Text('Momentan nu sunt promotii active.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _promotions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) =>
                  _buildPromotionTile(_promotions[index]),
            ),
      bottomNavigationBar: AppBottomNavigationBar(
        userId: widget.userId,
        userType: widget.userType,
        storeId: widget.storeId,
      ),
    );
  }
}

class ShoppingListPage extends StatefulWidget {
  final String userId;
  final int userType;

  const ShoppingListPage({
    super.key,
    required this.userId,
    this.userType = 0,
  });

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  List<dynamic> _products = [];
  bool _loading = true;
  final bool _status2Shown = false;
  String? _error;
  List<Map<String, dynamic>> _displayProducts = [];
  double _minTotal = 0.0;
  double _maxTotal = 0.0;
  List<Map<String, dynamic>> _singleStoreTotals = [];
  bool _hasUnavailablePrices = false;
  final Set<String> _quantityUpdatingKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _fetchShoppingList();
  }

  double? _parsePrice(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim().replaceAll(',', '.');
    if (text.isEmpty) {
      return null;
    }

    return double.tryParse(text);
  }

  int _parsePositiveInt(dynamic value, {int fallback = 1}) {
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  Map<String, Map<String, dynamic>> _selectApplicablePricesByStore(
    List<dynamic> prices,
    int quantity,
  ) {
    final applicablePrices = <String, Map<String, dynamic>>{};

    for (final price in prices) {
      final currentPrice = _parsePrice(price['actualPrice'] ?? price['price']);
      if (currentPrice == null || currentPrice <= 0) {
        continue;
      }

      final minimumQuantity = _parsePositiveInt(price['enGros']);
      if (minimumQuantity > quantity) {
        continue;
      }

      final storeName = price['store']?.toString() ?? '-';
      final existingSelection = applicablePrices[storeName];
      final existingMinimumQuantity = existingSelection == null
          ? 0
          : _parsePositiveInt(existingSelection['enGros']);
      final existingPrice = existingSelection == null
          ? null
          : _parsePrice(
              existingSelection['actualPrice'] ?? existingSelection['price'],
            );

      final shouldReplace =
          existingSelection == null ||
          minimumQuantity > existingMinimumQuantity ||
          (minimumQuantity == existingMinimumQuantity &&
              (existingPrice == null || currentPrice < existingPrice));

      if (shouldReplace) {
        applicablePrices[storeName] = Map<String, dynamic>.from(price);
      }
    }

    return applicablePrices;
  }

  String _formatPrice(double value) {
    final formatted = value.toStringAsFixed(2);
    if (formatted.endsWith('.00')) {
      return formatted.substring(0, formatted.length - 3);
    }
    if (formatted.endsWith('0')) {
      return formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  String _joinStores(List<String> storeNames) {
    if (storeNames.isEmpty) {
      return 'Fara pret disponibil';
    }
    if (storeNames.length == 1) {
      return storeNames.first;
    }
    if (storeNames.length == 2) {
      return '${storeNames[0]} sau ${storeNames[1]}';
    }
    final copy = List<String>.from(storeNames);
    final last = copy.removeLast();
    return '${copy.join(', ')} sau $last';
  }

  void _recalculateSummary() {
    final enriched = <Map<String, dynamic>>[];
    double total = 0.0;
    double maxTotal = 0.0;
    final storeTotals = <String, double>{};
    final storeCoverage = <String, int>{};
    bool hasUnavailablePrices = false;
    var consideredProducts = 0;

    for (final product in _products) {
      final prices = List<dynamic>.from(product['prices'] ?? []);
      final safeQuantity = _parsePositiveInt(product['quantity']);
      double? bestPrice;
      double? worstPrice;
      final bestStores = <String>[];
      final applicablePricesByStore = _selectApplicablePricesByStore(
        prices,
        safeQuantity,
      );

      consideredProducts += 1;

      for (final entry in applicablePricesByStore.entries) {
        final price = entry.value;
        final currentPrice = _parsePrice(
          price['actualPrice'] ?? price['price'],
        );
        if (currentPrice == null || currentPrice <= 0) {
          continue;
        }

        final storeName = entry.key;

        if (bestPrice == null || currentPrice < bestPrice) {
          bestPrice = currentPrice;
          bestStores
            ..clear()
            ..add(storeName);
        } else if (currentPrice == bestPrice &&
            !bestStores.contains(storeName)) {
          bestStores.add(storeName);
        }

        if (worstPrice == null || currentPrice > worstPrice) {
          worstPrice = currentPrice;
        }
      }

      if (bestPrice == null) {
        hasUnavailablePrices = true;
      } else {
        total += bestPrice * safeQuantity;
      }

      if (worstPrice != null) {
        maxTotal += worstPrice * safeQuantity;
      }

      applicablePricesByStore.forEach((storeName, selectedPrice) {
        final storePrice = _parsePrice(
          selectedPrice['actualPrice'] ?? selectedPrice['price'],
        );
        if (storePrice == null || storePrice <= 0) {
          return;
        }
        storeTotals[storeName] =
            (storeTotals[storeName] ?? 0.0) + (storePrice * safeQuantity);
        storeCoverage[storeName] = (storeCoverage[storeName] ?? 0) + 1;
      });

      final storeNames = List<String>.from(bestStores)..sort();
      enriched.add({
        ...Map<String, dynamic>.from(product),
        'quantity': safeQuantity,
        'cheapestPrice': bestPrice,
        'highestPrice': worstPrice,
        'cheapestStores': storeNames,
        'cheapestStoreLabel': _joinStores(storeNames),
      });
    }

    final singleStoreTotals =
        storeTotals.entries
            .where((entry) => storeCoverage[entry.key] == consideredProducts)
            .map(
              (entry) => <String, dynamic>{
                'store': entry.key,
                'total': entry.value,
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['total'] as double).compareTo(b['total'] as double),
          );

    setState(() {
      _displayProducts = enriched;
      _minTotal = total;
      _maxTotal = maxTotal;
      _singleStoreTotals = singleStoreTotals;
      _hasUnavailablePrices = hasUnavailablePrices;
    });
  }

  Future<void> _fetchShoppingList() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final url =
        'https://esprezzo.clusium.ro/api/endpoints/get_shopping_list.php?userid=${widget.userId}';
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final products = List<dynamic>.from(data['products'] ?? []);
        setState(() {
          _products = products;
        });
        _recalculateSummary();
      } else {
        setState(() {
          _error = 'Error: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load shopping list';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _openShoppingListProductDetails(Map<String, dynamic> product) {
    final productId = int.tryParse(
      (product['productId'] ?? product['ID'])?.toString() ?? '',
    );
    if (productId == null || productId <= 0) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ProductDetailsPage(productId: productId, userId: widget.userId),
      ),
    );
  }

  String _shoppingItemKey(dynamic itemId, dynamic status) {
    return '${itemId ?? '0'}_${status?.toString() ?? '0'}';
  }

  Future<void> _updateQuantity(
    dynamic productListId,
    int status,
    int newQuantity, {
    dynamic tagId,
    dynamic productId,
  }) async {
    if (newQuantity < 1) {
      return;
    }

    final itemKey = _shoppingItemKey(
      productListId ?? tagId ?? productId,
      status,
    );
    if (_quantityUpdatingKeys.contains(itemKey)) {
      return;
    }

    setState(() {
      _quantityUpdatingKeys.add(itemKey);
    });

    final url =
        'https://esprezzo.clusium.ro/api/endpoints/update_shopping_list_quantity.php';

    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': widget.userId,
          'productListId': productListId,
          'tagId': tagId,
          'productId': productId,
          'status': status,
          'quantity': newQuantity,
        }),
      );

      if (resp.statusCode == 200) {
        await _fetchShoppingList();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Eroare la actualizare cantitate: ${resp.body}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eroare la actualizare cantitate')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _quantityUpdatingKeys.remove(itemKey);
        });
      }
    }
  }

  Widget _buildShoppingProductCard(Map<String, dynamic> p) {
    final cheapestPrice = p['cheapestPrice'] as double?;
    final highestPrice = p['highestPrice'] as double?;
    final cheapestStoreLabel =
        p['cheapestStoreLabel']?.toString() ?? 'Fara pret disponibil';
    final status = int.tryParse(p['status']?.toString() ?? '1') ?? 1;
    final safeQuantity = _parsePositiveInt(p['quantity']);
    final itemKey = _shoppingItemKey(
      p['productListId'] ?? p['tagId'] ?? p['productId'],
      status,
    );
    final isUpdatingQuantity = _quantityUpdatingKeys.contains(itemKey);
    final tagId = p['tagId'];

    return Card(
      child: ListTile(
        onTap: () => _openShoppingListProductDetails(p),
        leading: p['photo'] != null && p['photo'].toString().isNotEmpty
            ? Image.network(
                'https://www.clusium.ro/photos/${p['photo']}',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              )
            : const Icon(Icons.image_not_supported),
        title: Row(
          children: [
            Expanded(child: Text(p['productName'] ?? '')),
            if (p['status'] == '1') ...[
              IconButton(
                icon: const Icon(
                  Icons.check_box_outline_blank,
                  color: Colors.black,
                ),
                tooltip: 'Marcheaza ca achizitionat',
                onPressed: () {
                  debugPrint(
                    "ShoppingListPage: status==1 for productId: ${p['productId']}",
                  );
                  _updateStatus(
                    p['productId'],
                    2,
                    productListId: p['productListId'],
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Sterge din lista',
                onPressed: () => _updateStatus(
                  p['productId'],
                  3,
                  productListId: p['productListId'],
                ),
              ),
            ] else if (p['status'] == '2') ...[
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: 'Achizitionat - marcheaza ca neachizitionat',
                onPressed: () => _updateStatus(
                  p['productId'],
                  1,
                  productListId: p['productListId'],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Sterge din lista',
                onPressed: () => _updateStatus(
                  p['productId'],
                  3,
                  productListId: p['productListId'],
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Cantitate:'),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Scade cantitatea',
                  onPressed: isUpdatingQuantity || safeQuantity <= 1
                      ? null
                      : () => _updateQuantity(
                          p['productListId'] ?? p['productId'],
                          status,
                          safeQuantity - 1,
                          tagId: tagId,
                          productId: p['productId'],
                        ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$safeQuantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Creste cantitatea',
                  onPressed: isUpdatingQuantity
                      ? null
                      : () => _updateQuantity(
                          p['productListId'] ?? p['productId'],
                          status,
                          safeQuantity + 1,
                          tagId: tagId,
                          productId: p['productId'],
                        ),
                ),
                if (isUpdatingQuantity) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            Text(
              cheapestPrice != null
                  ? 'Pret minim: ${_formatPrice(cheapestPrice)} lei'
                  : 'Pret minim: indisponibil',
            ),
            if (highestPrice != null)
              Text('Pret maxim: ${_formatPrice(highestPrice)} lei'),
            Text('Disponibil in: $cheapestStoreLabel'),
            if (p['dueDate'] != null) Text('Due: ${p['dueDate']}'),
            if (p['onlyPromo'] == 1)
              const Text('Promo', style: TextStyle(color: Colors.blue)),
          ],
        ),
      ),
    );
  }

  Widget _buildShoppingSectionSeparator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: const [
          Expanded(child: Divider(thickness: 1.2)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'Puse deja in cos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Divider(thickness: 1.2)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lista cumparaturi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _products.isEmpty
          ? const Center(child: Text('Lista este goala.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24.0),
              children: [
                ...(() {
                  final widgets = <Widget>[];
                  var hasActiveItems = false;
                  var separatorInserted = false;

                  for (final product in _displayProducts) {
                    final status =
                        int.tryParse(product['status']?.toString() ?? '') ?? 0;
                    if (status == 1) {
                      hasActiveItems = true;
                    }
                    if (!separatorInserted && hasActiveItems && status == 2) {
                      widgets.add(_buildShoppingSectionSeparator());
                      separatorInserted = true;
                    }
                    widgets.add(_buildShoppingProductCard(product));
                  }

                  return widgets;
                }()),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total minim: ${_formatPrice(_minTotal)} lei',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Total maxim: ${_formatPrice(_maxTotal)} lei',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_singleStoreTotals.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ..._singleStoreTotals.map(
                              (storeTotal) => Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Total ${storeTotal['store']}: ${_formatPrice(storeTotal['total'] as double)} lei',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ),
                          ],
                          if (_hasUnavailablePrices)
                            const Padding(
                              padding: EdgeInsets.only(top: 6.0),
                              child: Text(
                                'Atentie: exista produse fara pret disponibil.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: AppBottomNavigationBar(
        userId: widget.userId,
        userType: widget.userType,
      ),
    );
  }

  Future<void> _updateStatus(
    dynamic productId,
    int status, {
    dynamic productListId,
  }) async {
    final url =
        'https://esprezzo.clusium.ro/api/endpoints/update_shopping_list_status.php';
    debugPrint(
      '[update_shopping_list_status] userId: ${widget.userId}, productId: $productId, productListId: $productListId, status: $status',
    );
    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': widget.userId,
          'productId': productId,
          'productListId': productListId,
          'status': status,
        }),
      );
      if (resp.statusCode == 200) {
        _fetchShoppingList(); // Refresh list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la actualizare: ${resp.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eroare la actualizare status')),
      );
    }
  }
}

class ProductDetailsPage extends StatefulWidget {
  final int productId;
  final String? userId;
  final int? storeId;
  const ProductDetailsPage({
    super.key,
    required this.productId,
    this.userId,
    this.storeId,
  });

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  bool _loading = true;
  String? _authToken;
  int _userType = 0;
  String? _error;
  Map<String, dynamic>? _product;
  List<dynamic> _prices = [];
  bool _priceLoading = false;
  List<dynamic> _related = [];
  List<dynamic> _subcategoryProducts = [];
  Map<String, dynamic>? _category;
  bool _isFavorite = false;
  List<dynamic> _allStores = [];

  @override
  void initState() {
    super.initState();
    _loadAuthToken();
    _fetchDetails();
    _fetchAllStores();
  }

  Future<void> _loadAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _authToken = prefs.getString('authToken');
      });
    }
  }

  Future<void> _fetchAllStores() async {
    try {
      final response = await http.get(
        Uri.parse('https://esprezzo.clusium.ro/api/endpoints/get_stores.php'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _allStores = data['stores'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching stores: $e');
    }
  }

  String _getStoreNameById(int storeId) {
    for (final store in _allStores) {
      if (int.tryParse(store['ID']?.toString() ?? '0') == storeId) {
        return store['location']?.toString() ?? '-';
      }
    }
    return '-';
  }

  bool _selectedStoreHasPrice() {
    if (widget.storeId == null) return false;
    for (final price in _prices) {
      if (int.tryParse(price['storeId']?.toString() ?? '0') == widget.storeId) {
        return true;
      }
    }
    return false;
  }

  bool _hasPlaceholderBarcode() {
    final barcode = _product?['barcode']?.toString();
    return barcode != null && RegExp(r'^0+$').hasMatch(barcode);
  }

  bool get _canEditPrices =>
      _userType >= 1 && _authToken != null && _authToken!.isNotEmpty;

  bool get _canEditProducts =>
      _userType >= 2 && _authToken != null && _authToken!.isNotEmpty;

  Future<String?> _scanBarcodeForEditing() async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scaneaza codul de bare'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.isNotEmpty) {
                  Navigator.of(dialogContext).pop(value);
                  return;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editBarcode() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final barcode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editeaza codul de bare'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Cod de bare',
                suffixIcon: IconButton(
                  tooltip: 'Scaneaza cu camera',
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: () async {
                    final scannedBarcode = await _scanBarcodeForEditing();
                    if (scannedBarcode != null) {
                      controller.text = scannedBarcode;
                      setDialogState(() {});
                    }
                  },
                ),
              ),
              validator: (value) {
                final trimmedValue = value?.trim() ?? '';
                if (!RegExp(r'^\d+$').hasMatch(trimmedValue)) {
                  return 'Introdu un cod format doar din cifre';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Renunta'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(controller.text.trim());
                }
              },
              child: const Text('Salveaza'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (barcode == null) return;

    try {
      final response = await http.post(
        Uri.parse(
          'https://esprezzo.clusium.ro/api/endpoints/update_barcode.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': widget.userId,
          'authToken': _authToken,
          'productId': widget.productId,
          'barcode': barcode,
        }),
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        setState(() {
          _product?['barcode'] = data['barcode'];
          _product?['barcodeSearch'] = data['barcodeSearch'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Codul de bare a fost actualizat.')),
        );
      } else {
        throw Exception(data['error'] ?? 'Nu s-a putut actualiza codul.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la actualizarea codului: $e')),
      );
    }
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    String userIdParam = '';
    String storeIdParam = '';
    String? userId = widget.userId;
    int? storeId = widget.storeId;
    debugPrint(
      'ProductDetailsPage: found userId=${userId ?? 'null'}, storeId=${storeId ?? 'null'}',
    );
    if (userId != null && userId.isNotEmpty) {
      userIdParam = '&userId=${Uri.encodeComponent(userId)}';
    }
    if (storeId != null) {
      storeIdParam = '&storeId=$storeId';
    }
    debugPrint(
      'Calling product details API with productId=${widget.productId}${userIdParam.isNotEmpty ? ', userId=${userId!}' : ''}${storeIdParam.isNotEmpty ? ', storeId=$storeId' : ''}',
    );
    try {
      final response = await http.get(
        Uri.parse(
          'https://esprezzo.clusium.ro/api/endpoints/products.php?productId=${widget.productId}$userIdParam$storeIdParam',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _product = data['product'];
          _userType = int.tryParse(data['userType']?.toString() ?? '') ?? 0;
          _prices = data['prices'] ?? [];
          _related = data['related'] ?? [];
          _subcategoryProducts = data['subcategoryProducts'] ?? [];
          _category = data['category'];
          _isFavorite = data['favorite'] == 1;
        });
      } else {
        setState(() {
          _error = 'Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load product details';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _addToShoppingListFromDetails() async {
    if (widget.userId == null || widget.userId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trebuie sa fii autentificat.')),
      );
      return;
    }

    final productId =
        _product?['ID']?.toString() ?? widget.productId.toString();
    final url =
        'https://esprezzo.clusium.ro/api/endpoints/add_to_shopping_list.php';
    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': widget.userId,
          'productId': productId,
          'storeId': widget.storeId ?? 0,
          'listName': 'Lista cumparaturi',
        }),
      );
      final respJson = json.decode(resp.body);
      if (resp.statusCode == 200 && respJson['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produs adaugat la lista!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Eroare la adaugare: ${respJson['error'] ?? 'necunoscuta'}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exceptie la adaugare: $e')));
    }
  }

  Future<void> _toggleFavoriteFromDetails() async {
    if (widget.userId == null || widget.userId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trebuie sa fii autentificat.')),
      );
      return;
    }

    final productId =
        (int.tryParse(_product?['ID']?.toString() ?? '') ?? widget.productId);
    final url = _isFavorite
        ? 'https://esprezzo.clusium.ro/api/endpoints/remove_favorite.php'
        : 'https://esprezzo.clusium.ro/api/endpoints/add_favorite.php';

    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': widget.userId, 'productId': productId}),
      );
      final respJson = json.decode(resp.body);
      if (resp.statusCode == 200 && respJson['success'] == true) {
        setState(() {
          _isFavorite = !_isFavorite;
          if (_product != null) {
            _product!['favorite'] = _isFavorite ? 1 : 0;
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Eroare la actualizare favorite: '
              '${respJson['error'] ?? 'necunoscuta'}',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exceptie la favorite: $e')));
    }
  }

  Future<void> _addOrUpdatePrice(
    int storeId,
    String storeName,
    String? price,
    String? enGros,
  ) async {
    debugPrint(
      'Opening price dialog for storeId=$storeId, storeName=$storeName, price=$price, enGros=$enGros',
    );
    TextEditingController priceController = TextEditingController(
      text: price ?? '',
    );
    TextEditingController enGrosController = TextEditingController(
      text: enGros ?? '1',
    );

    try {
      await showDialog(
        context: context,
        builder: (context) {
          bool promo = false;
          TextEditingController discountPriceController =
              TextEditingController();
          TextEditingController startDateController = TextEditingController();
          TextEditingController endDateController = TextEditingController();
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(
                  '${price == null ? 'Adauga' : 'Editeaza'} pret pentru $storeName',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: priceController,
                        decoration: const InputDecoration(
                          labelText: 'Pret (lei)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      TextField(
                        controller: enGrosController,
                        decoration: const InputDecoration(
                          labelText: 'EnGros (bucati)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Promo', style: TextStyle(fontSize: 16)),
                          Switch(
                            value: promo,
                            onChanged: (v) {
                              setState(() {
                                promo = v;
                              });
                            },
                          ),
                        ],
                      ),
                      if (promo) ...[
                        TextField(
                          controller: discountPriceController,
                          decoration: const InputDecoration(
                            labelText: 'Pret discount',
                          ),
                          keyboardType: TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: startDateController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Data start discount',
                          ),
                          onTap: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() {
                                startDateController.text = picked
                                    .toIso8601String()
                                    .split('T')[0];
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: endDateController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Data terminare discount',
                          ),
                          onTap: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() {
                                endDateController.text = picked
                                    .toIso8601String()
                                    .split('T')[0];
                              });
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Renunta'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        _priceLoading = true;
                      });
                      debugPrint(
                        'Sending price to API: productId=${widget.productId}, storeId=$storeId, price=${priceController.text}, enGros=${enGrosController.text}',
                      );
                      try {
                        final priceValue = double.tryParse(
                          priceController.text,
                        );
                        final enGrosValue = int.tryParse(enGrosController.text);
                        if (priceValue == null || enGrosValue == null) {
                          /* ...existing code... */
                        }
                        // Prepare promo fields
                        double? discountPrice = promo
                            ? double.tryParse(discountPriceController.text)
                            : null;
                        String? startDate = promo
                            ? startDateController.text
                            : null;
                        String? endDate = promo ? endDateController.text : null;
                        final resp = await http.post(
                          Uri.parse(
                            'https://esprezzo.clusium.ro/api/endpoints/add_or_update_price.php',
                          ),
                          headers: {'Content-Type': 'application/json'},
                          body: json.encode({
                            'userId': widget.userId,
                            'authToken': _authToken,
                            'productId': widget.productId,
                            'storeId': storeId,
                            'price': priceValue,
                            'enGros': enGrosValue,
                            'promo': promo ? 1 : 0,
                            'discountPrice': discountPrice,
                            'discountStart': startDate,
                            'discountEnd': endDate,
                          }),
                        );
                        debugPrint(
                          'API response: status=${resp.statusCode}, body=${resp.body}',
                        );
                        setState(() {
                          _priceLoading = false;
                        });
                        final respJson = json.decode(resp.body);
                        if (resp.statusCode == 200 &&
                            respJson['success'] == true) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Pret salvat cu succes!')),
                          );
                          await _fetchDetails();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Eroare la salvare pret: \nStatus: ${resp.statusCode}\n${respJson['error'] ?? 'necunoscuta'}\nBody: ${resp.body}',
                              ),
                            ),
                          );
                        }
                      } catch (e, st) {
                        debugPrint('Exception during price API call: $e\n$st');
                        setState(() {
                          _priceLoading = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Exceptie la salvare pret: $e'),
                          ),
                        );
                      }
                    },
                    child: const Text('Salveaza'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e, st) {
      debugPrint('Exception during price API call: $e\n$st');
      setState(() {
        _priceLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exceptie la salvare pret: $e')));
    }
  }

  void _showAddPriceForNewStore() {
    // Get store IDs that already have prices
    final storesWithPrices = <int>{};
    for (final price in _prices) {
      final storeId = int.tryParse(price['storeId']?.toString() ?? '0');
      if (storeId != null) {
        storesWithPrices.add(storeId);
      }
    }

    // Get stores without prices
    final availableStores = <Map<String, dynamic>>[];
    for (final store in _allStores) {
      final storeId = int.tryParse(store['ID']?.toString() ?? '0');
      if (storeId != null && !storesWithPrices.contains(storeId)) {
        availableStores.add(store);
      }
    }

    if (availableStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Toate magazinele au deja preturi pentru acest produs.',
          ),
        ),
      );
      return;
    }

    // Show dialog with stores
    int? selectedStoreId;
    String? selectedStoreName;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Adauga pret pentru alt magazin'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<int>(
                      isExpanded: true,
                      hint: const Text('Selecteaza magazin'),
                      value: selectedStoreId,
                      items: availableStores.map((store) {
                        final id = int.tryParse(store['ID']?.toString() ?? '0');
                        final name = store['location']?.toString() ?? '-';
                        return DropdownMenuItem(value: id, child: Text(name));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          final store = availableStores.firstWhere(
                            (s) =>
                                int.tryParse(s['ID']?.toString() ?? '0') ==
                                value,
                            orElse: () => {},
                          );
                          setState(() {
                            selectedStoreId = value;
                            selectedStoreName = store['location']?.toString();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Renunta'),
                ),
                ElevatedButton(
                  onPressed: selectedStoreId != null
                      ? () {
                          Navigator.of(context).pop();
                          _addOrUpdatePrice(
                            selectedStoreId!,
                            selectedStoreName ?? '-',
                            null,
                            '1',
                          );
                        }
                      : null,
                  child: const Text('Continua'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> _groupPricesByStore() {
    final Map<String, List<dynamic>> grouped = {};
    for (final price in _prices) {
      final key = price['storeId']?.toString() ?? '';
      grouped.putIfAbsent(key, () => <dynamic>[]).add(price);
    }

    return grouped.entries.map((entry) {
      final prices = List<dynamic>.from(entry.value);
      return <String, dynamic>{
        'storeId': entry.key,
        'store': prices.isNotEmpty
            ? prices.first['store']?.toString() ?? '-'
            : '-',
        'prices': prices,
      };
    }).toList();
  }

  Widget _buildPriceTierTile(dynamic p, {required bool isSelectedStore}) {
    DateTime? priceDate;
    if (p['date'] != null && p['date'].toString().isNotEmpty) {
      try {
        priceDate = DateTime.parse(p['date']);
      } catch (_) {}
    }

    String ageText = '';
    Color ageColor = Colors.lightGreen;
    if (priceDate != null) {
      final now = DateTime.now();
      final diff = now.difference(priceDate);
      if (diff.inDays > 90) {
        ageText = 'pret mai vechi de 3 luni';
        ageColor = const Color.fromARGB(255, 255, 0, 0);
      } else if (diff.inDays > 30) {
        ageText = 'pret mai vechi de o luna';
        ageColor = const Color.fromARGB(255, 255, 127, 0);
      } else if (diff.inDays > 7) {
        ageText = 'pret mai vechi de o saptamana';
        ageColor = const Color.fromARGB(255, 0, 255, 0);
      } else if (diff.inDays >= 1) {
        ageText = 'pret din ultima saptamana';
        ageColor = const Color.fromARGB(255, 0, 192, 0);
      } else {
        ageText = 'pret astazi';
        ageColor = const Color.fromARGB(255, 0, 128, 0);
      }
    }

    final storeId = int.tryParse(p['storeId']?.toString() ?? '0') ?? 0;
    final storeName = p['store']?.toString() ?? '-';
    final actualPrice = p['actualPrice']?.toString();
    final basePrice = p['price']?.toString();
    final enGros = p['enGros']?.toString() ?? '1';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: CircleAvatar(
        backgroundColor: Colors.deepPurple.withValues(alpha: 0.08),
        child: Text(
          enGros,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              actualPrice != null ? '$actualPrice lei' : 'Fara pret',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          if (basePrice != null &&
              actualPrice != null &&
              basePrice != actualPrice)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                '$basePrice lei',
                style: const TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: Colors.red,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cantitate: $enGros buc'),
          if (ageText.isNotEmpty)
            Text(ageText, style: TextStyle(color: ageColor, fontSize: 12)),
          if (p['discountedPrice'] != null && p['typeDiscount'] != null)
            Text(
              'Promo activ: ${p['discountedPrice']} lei',
              style: const TextStyle(fontSize: 12, color: Colors.blue),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canEditPrices) ...[
            if (isSelectedStore && actualPrice != null)
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green, size: 20),
                tooltip: 'Confirma pret actual',
                onPressed: () async {
                  DateTime? currentPriceDate;
                  if (p['date'] != null && p['date'].toString().isNotEmpty) {
                    try {
                      currentPriceDate = DateTime.parse(p['date']);
                    } catch (_) {}
                  }
                  if (currentPriceDate != null) {
                    final now = DateTime.now();
                    final diff = now.difference(currentPriceDate);
                    if (diff.inDays > 1) {
                      await _addOrUpdatePrice(
                        storeId,
                        storeName,
                        actualPrice,
                        enGros,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Pretul este deja actualizat pentru astazi.',
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            IconButton(
              icon: Icon(actualPrice == null ? Icons.add : Icons.edit),
              tooltip: actualPrice == null ? 'Adauga pret' : 'Editeaza pret',
              onPressed: () =>
                  _addOrUpdatePrice(storeId, storeName, actualPrice, enGros),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStorePriceCard({
    required bool isSelectedStore,
    required Widget child,
  }) {
    return Card(
      color: isSelectedStore ? Colors.deepPurple.withValues(alpha: 0.08) : null,
      elevation: isSelectedStore ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelectedStore
              ? Colors.deepPurple.withValues(alpha: 0.45)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_product?['productName'] ?? 'Detalii produs')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_product != null) ...[
                    Row(
                      children: [
                        _product!['photo'] != null &&
                                _product!['photo'].toString().isNotEmpty
                            ? Image.network(
                                'https://www.clusium.ro/photos/${_product!['photo']}',
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image_not_supported, size: 120),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _product!['productName'] ?? '',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 2,
                                children: [
                                  Text(
                                    'Cod bare: ${_product!['barcode'] ?? '-'}',
                                  ),
                                    if (_canEditProducts &&
                                      _hasPlaceholderBarcode())
                                    IconButton(
                                      tooltip: 'Editeaza codul de bare',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      onPressed: _editBarcode,
                                    ),
                                ],
                              ),
                              if (_product!['tags'] != null &&
                                  _product!['tags']
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: List<Widget>.from(
                                    (_product!['tags'] is List
                                            ? (_product!['tags'] as List)
                                            : (_product!['tags']
                                                  .toString()
                                                  .split(',')
                                                  .map((t) => t.trim())
                                                  .where((t) => t.isNotEmpty)
                                                  .toList()))
                                        .map(
                                          (tag) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.cyan,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              tag.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              if (_category != null) ...[
                                Text(
                                  'Subcategorie: ${_category!['subcategory']}',
                                ),
                                GestureDetector(
                                  onTap: () {
                                    // TODO: Implement navigation to main category products
                                  },
                                  child: Text(
                                    'Categorie principală: ${_category!['category']}',
                                    style: const TextStyle(color: Colors.blue),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (widget.userId != null && widget.userId!.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _addToShoppingListFromDetails,
                              icon: const Icon(Icons.shopping_cart_outlined),
                              label: const Text('Adauga in cos'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _toggleFavoriteFromDetails,
                              icon: Icon(
                                _isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _isFavorite ? Colors.red : null,
                              ),
                              label: Text(_isFavorite ? 'Favorit' : 'Favorite'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Preturi in magazine',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ProductPriceHistoryPage(
                                productId: widget.productId,
                                productName:
                                    _product?['productName']?.toString() ?? '',
                                userId: widget.userId,
                                userType: _userType,
                                storeId: widget.storeId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('Istorie pret'),
                      ),
                    ),
                    if (_prices.isNotEmpty)
                      ..._groupPricesByStore().map((group) {
                        final storePrices = group['prices'] as List<dynamic>;
                        final storeId =
                            int.tryParse(group['storeId']?.toString() ?? '0') ??
                            0;
                        final isSelectedStore =
                            widget.storeId != null && storeId == widget.storeId;

                        if (storePrices.length == 1) {
                          return _buildStorePriceCard(
                            isSelectedStore: isSelectedStore,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 12.0,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      group['store']?.toString() ?? '-',
                                      textAlign: TextAlign.left,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: _buildPriceTierTile(
                                    storePrices.first,
                                    isSelectedStore: isSelectedStore,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return _buildStorePriceCard(
                          isSelectedStore: isSelectedStore,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            group['store']?.toString() ?? '-',
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const Text(
                                            'Pret cascada',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              ...storePrices.map(
                                (p) => _buildPriceTierTile(
                                  p,
                                  isSelectedStore: isSelectedStore,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    if (_prices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text('Nu exista preturi pentru acest produs.'),
                      ),
                    if (_canEditPrices &&
                      widget.storeId != null &&
                      !_selectedStoreHasPrice())
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: ElevatedButton(
                          onPressed: () {
                            final selectedStoreName = _getStoreNameById(
                              widget.storeId!,
                            );
                            _addOrUpdatePrice(
                              widget.storeId!,
                              selectedStoreName,
                              null,
                              '1',
                            );
                          },
                          child: Text(
                            'Adauga pret pentru ${_getStoreNameById(widget.storeId!)}',
                          ),
                        ),
                      ),
                    if (_canEditPrices && _allStores.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: ElevatedButton(
                          onPressed: _showAddPriceForNewStore,
                          child: const Text('Adauga pret pentru alt magazin'),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Produse similare',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ..._related.map(
                      (prod) => ListTile(
                        leading:
                            prod['photo'] != null &&
                                prod['photo'].toString().isNotEmpty
                            ? Image.network(
                                'https://www.clusium.ro/photos/${prod['photo']?.toString() ?? 'no-image.png'}',
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image_not_supported, size: 60),
                        title: Text(prod['productName'] ?? ''),
                        subtitle: Text(
                          '${_category!['category']} > ${_category!['subcategory']}',
                        ),
                        onTap: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => ProductDetailsPage(
                                productId:
                                    int.tryParse(
                                      prod['ID']?.toString() ?? '0',
                                    ) ??
                                    0,
                                userId: widget.userId,
                                storeId: widget.storeId,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Toate produsele din subcategorie',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ..._subcategoryProducts.map(
                      (prod) => ListTile(
                        leading:
                            prod['photo'] != null &&
                                prod['photo'].toString().isNotEmpty
                            ? Image.network(
                                'https://www.clusium.ro/photos/${prod['photo']?.toString() ?? 'no-image.png'}',
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image_not_supported, size: 60),
                        title: Text(prod['productName'] ?? ''),
                        subtitle: Text(
                          '${_category!['category']} > ${_category!['subcategory']}',
                        ),
                        onTap: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => ProductDetailsPage(
                                productId:
                                    int.tryParse(
                                      prod['ID']?.toString() ?? '0',
                                    ) ??
                                    0,
                                userId: widget.userId,
                                storeId: widget.storeId,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: AppBottomNavigationBar(
        userId: widget.userId,
        userType: _userType,
      ),
    );
  }
}

class ProductPriceHistoryPage extends StatefulWidget {
  final int productId;
  final String productName;
  final String? userId;
  final int userType;
  final int? storeId;

  const ProductPriceHistoryPage({
    super.key,
    required this.productId,
    required this.productName,
    this.userId,
    this.userType = 0,
    this.storeId,
  });

  @override
  State<ProductPriceHistoryPage> createState() =>
      _ProductPriceHistoryPageState();
}

class _ProductPriceHistoryPageState extends State<ProductPriceHistoryPage> {
  List<dynamic> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPriceHistory();
  }

  Future<void> _fetchPriceHistory() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://esprezzo.clusium.ro/api/endpoints/get_price_history.php?productId=${widget.productId}',
        ),
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _history = List<dynamic>.from(data['history'] ?? []);
        });
      } else {
        setState(() {
          _error = 'Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Nu s-a putut incarca istoria preturilor.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatDate(dynamic value) {
    final rawDate = value?.toString() ?? '';
    final date = DateTime.tryParse(rawDate);
    if (date == null) return rawDate;

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Istorie pret')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _history.isEmpty
          ? const Center(
              child: Text('Nu exista istoric de pret pentru acest produs.'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = _history[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      item['store']?.toString() ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_formatDate(item['date'])} · Cantitate: ${item['enGros'] ?? 1} buc',
                    ),
                    trailing: Text(
                      '${item['price'] ?? '-'} lei',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: AppBottomNavigationBar(
        userId: widget.userId,
        userType: widget.userType,
        storeId: widget.storeId,
      ),
    );
  }
}

class AccountPage extends StatefulWidget {
  final String userId;
  final String username;
  final String appVersion;
  final int userType;

  const AccountPage({
    super.key,
    required this.userId,
    required this.username,
    required this.appVersion,
    this.userType = 0,
  });

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _favoriteProducts = [];
  bool _loadingFavorites = false;
  String? _errorFavorites;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _favoriteProducts.isEmpty) {
        _fetchFavorites();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('userId');
    await prefs.remove('userType');
    await prefs.remove('authToken');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const ProductSearchPage()),
      (route) => false,
    );
  }

  Future<void> _fetchFavorites() async {
    setState(() {
      _loadingFavorites = true;
      _errorFavorites = null;
    });
    final url =
        'https://esprezzo.clusium.ro/api/endpoints/get_favorites.php?userId=${widget.userId}';
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        setState(() {
          _favoriteProducts = data['products'] ?? [];
        });
      } else {
        setState(() {
          _errorFavorites = 'Error: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorFavorites = 'Failed to load favorites';
      });
    } finally {
      setState(() {
        _loadingFavorites = false;
      });
    }
  }

  void _openProductDetails(dynamic product) {
    final productId = product['ID'] ?? product['ID'];
    if (productId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProductDetailsPage(
            productId: int.tryParse(productId.toString()) ?? 0,
            userId: widget.userId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contul meu'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Profil'),
            Tab(icon: Icon(Icons.favorite), text: 'Favorite'),
            Tab(icon: Icon(Icons.edit), text: 'Editare'),
            Tab(icon: Icon(Icons.info), text: 'Despre'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Profil
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informații cont',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Utilizator: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Expanded(child: Text(widget.username)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text(
                              'ID utilizator: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Expanded(child: Text(widget.userId)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text(
                              'Versiune aplicație: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Expanded(child: Text(widget.appVersion)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Deconectare'),
                ),
              ],
            ),
          ),
          // Tab 2: Favorite
          _loadingFavorites
              ? const Center(child: CircularProgressIndicator())
              : _errorFavorites != null
              ? Center(
                  child: Text(
                    _errorFavorites!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : _favoriteProducts.isEmpty
              ? const Center(child: Text('Nu aveți produse favorite.'))
              : ListView.builder(
                  itemCount: _favoriteProducts.length,
                  itemBuilder: (context, index) {
                    final product = _favoriteProducts[index];
                    final photoUrl =
                        'https://www.clusium.ro/photos/${product['photo']?.toString() ?? 'no-image.png'}';
                    return Card(
                      child: ListTile(
                        leading:
                            product['photo'] != null &&
                                product['photo'].toString().isNotEmpty
                            ? Image.network(
                                photoUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image_not_supported),
                        title: Text(product['productName'] ?? 'No name'),
                        subtitle: Text(
                          '${product['category'] ?? '-'} > ${product['subcategory'] ?? '-'}',
                        ),
                        onTap: () => _openProductDetails(product),
                      ),
                    );
                  },
                ),
          // Tab 3: Editare cont
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Editare cont',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Parola nouă',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Funcționalitate în dezvoltare'),
                      ),
                    );
                  },
                  child: const Text('Salvează Changes'),
                ),
              ],
            ),
          ),
          // Tab 4: Despre
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Despre aplicație',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Esprezzo',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Versiune: ${widget.appVersion}'),
                        const SizedBox(height: 12),
                        const Text(
                          'O aplicație mobilă pentru căutarea și compararea prețurilor produselor în diferite magazine, gestionarea listelor de cumpărături și descoperirea produselor favorite.',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Funcționalități:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text('• Scanare cod bare'),
                        const Text('• Căutare produse'),
                        const Text('• Comparare prețuri pe magazine'),
                        const Text('• Gestionare liste de cumpărături'),
                        const Text('• Marcare produse favorite'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        userId: widget.userId,
        userType: widget.userType,
      ),
    );
  }
}
