import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _firebaseAvailable = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoodFindApp());
}

class AppColors {
  static const Color bg = Color(0xFFF5F6FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFFFF7A00);
  static const Color secondary = Color(0xFF176B45);
  static const Color text = Color(0xFF202124);
  static const Color muted = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC2626);
}

String formatPrice(double amount) => '₱${amount.toStringAsFixed(2)}';

class FoodFindMark extends StatelessWidget {
  const FoodFindMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/foodfind_mark.svg',
    width: size,
    height: size,
    fit: BoxFit.contain,
  );
}

class FoodFindBrand extends StatelessWidget {
  const FoodFindBrand({
    required this.markSize,
    required this.titleSize,
    this.showTagline = false,
    super.key,
  });

  final double markSize;
  final double titleSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FoodFindMark(size: markSize),
      const SizedBox(height: 14),
      Text(
        'FoodFind',
        style: GoogleFonts.poppins(
          fontSize: titleSize,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      if (showTagline) ...[
        const SizedBox(height: 8),
        Text(
          'Discover Food. Order Easily. Enjoy Every Bite.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.muted),
        ),
      ],
    ],
  );
}

class FoodFindImage extends StatelessWidget {
  const FoodFindImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.icon = Icons.restaurant_rounded,
    super.key,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData icon;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: url,
    width: width,
    height: height,
    fit: fit,
    placeholder: (_, _) => _placeholder(),
    errorWidget: (_, _, _) => _placeholder(),
  );

  Widget _placeholder() => Container(
    width: width,
    height: height,
    color: AppColors.bg,
    alignment: Alignment.center,
    child: Icon(icon, color: AppColors.muted),
  );
}

class FoodFindApp extends StatelessWidget {
  const FoodFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FoodAppState()..boot(),
      child: MaterialApp(
        title: 'FoodFind',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            secondary: AppColors.secondary,
          ),
          textTheme: ThemeData.light().textTheme,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    this.phone = '',
    this.address = '',
  });

  final String name;
  final String email;
  final String phone;
  final String address;

  factory UserProfile.empty() =>
      const UserProfile(name: 'Guest', email: '', phone: '', address: '');
}

class Restaurant {
  const Restaurant({
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.rating,
    required this.eta,
    required this.deliveryFee,
    required this.isOpen,
  });

  final String name;
  final String category;
  final String imageUrl;
  final double rating;
  final String eta;
  final double deliveryFee;
  final bool isOpen;
}

class FoodItem {
  const FoodItem({
    required this.name,
    required this.restaurant,
    required this.imageUrl,
    required this.category,
    required this.description,
    required this.price,
    required this.rating,
    required this.isPopular,
  });

  final String name;
  final String restaurant;
  final String imageUrl;
  final String category;
  final String description;
  final double price;
  final double rating;
  final bool isPopular;

  Map<String, dynamic> toJson() => {
    'name': name,
    'restaurant': restaurant,
    'imageUrl': imageUrl,
    'category': category,
    'description': description,
    'price': price,
    'rating': rating,
    'isPopular': isPopular,
  };

  factory FoodItem.fromJson(Map<String, dynamic> json) => FoodItem(
    name: json['name'] as String,
    restaurant: json['restaurant'] as String,
    imageUrl: json['imageUrl'] as String,
    category: json['category'] as String,
    description: json['description'] as String,
    price: (json['price'] as num).toDouble(),
    rating: (json['rating'] as num).toDouble(),
    isPopular: json['isPopular'] as bool,
  );
}

class CartEntry {
  const CartEntry({required this.food, required this.quantity});

  final FoodItem food;
  final int quantity;

  CartEntry copyWith({int? quantity}) =>
      CartEntry(food: food, quantity: quantity ?? this.quantity);

  Map<String, dynamic> toJson() => {
    'food': food.toJson(),
    'quantity': quantity,
  };

  factory CartEntry.fromJson(Map<String, dynamic> json) => CartEntry(
    food: FoodItem.fromJson(Map<String, dynamic>.from(json['food'] as Map)),
    quantity: (json['quantity'] as num).toInt().clamp(1, 99).toInt(),
  );
}

const List<String> kOrderStatuses = [
  'Order Placed',
  'Preparing Your Food',
  'Ready for Pickup',
  'Out for Delivery',
  'Delivered',
];

class FoodOrder {
  const FoodOrder({
    required this.reference,
    required this.createdAt,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.statusIndex,
  });

  final String reference;
  final DateTime createdAt;
  final String customerName;
  final String phone;
  final String address;
  final String paymentMethod;
  final List<CartEntry> items;
  final double subtotal;
  final double deliveryFee;
  final int statusIndex;

  double get total => subtotal + deliveryFee;
  String get status => kOrderStatuses[statusIndex.clamp(0, 4).toInt()];

  FoodOrder copyWith({int? statusIndex}) => FoodOrder(
    reference: reference,
    createdAt: createdAt,
    customerName: customerName,
    phone: phone,
    address: address,
    paymentMethod: paymentMethod,
    items: items,
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    statusIndex: statusIndex ?? this.statusIndex,
  );

  Map<String, dynamic> toJson() => {
    'reference': reference,
    'createdAt': createdAt.toIso8601String(),
    'customerName': customerName,
    'phone': phone,
    'address': address,
    'paymentMethod': paymentMethod,
    'items': items.map((item) => item.toJson()).toList(),
    'subtotal': subtotal,
    'deliveryFee': deliveryFee,
    'statusIndex': statusIndex,
  };

  factory FoodOrder.fromJson(Map<String, dynamic> json) => FoodOrder(
    reference: json['reference'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    customerName: json['customerName'] as String,
    phone: json['phone'] as String,
    address: json['address'] as String,
    paymentMethod: json['paymentMethod'] as String,
    items: (json['items'] as List<dynamic>)
        .map((item) => CartEntry.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
    subtotal: (json['subtotal'] as num).toDouble(),
    deliveryFee: (json['deliveryFee'] as num).toDouble(),
    statusIndex: (json['statusIndex'] as num).toInt().clamp(0, 4).toInt(),
  );
}

const List<String> kCategories = [
  'All',
  'Burgers',
  'Pizza',
  'Chicken',
  'Rice Meals',
  'Pasta',
  'Drinks',
  'Desserts',
  'Snacks',
];

const List<Restaurant> kRestaurants = [
  Restaurant(
    name: 'Aristocrat',
    category: 'Rice Meals',
    imageUrl: 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=1200&q=80',
    rating: 4.8,
    eta: '18-25 min',
    deliveryFee: 35,
    isOpen: true,
  ),
  Restaurant(
    name: 'Bistro 88',
    category: 'Pizza',
    imageUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
    rating: 4.7,
    eta: '20-30 min',
    deliveryFee: 40,
    isOpen: true,
  ),
  Restaurant(
    name: 'Burger Hub',
    category: 'Burgers',
    imageUrl: 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=1200&q=80',
    rating: 4.9,
    eta: '15-20 min',
    deliveryFee: 25,
    isOpen: true,
  ),
  Restaurant(
    name: 'Green Bowl',
    category: 'Rice Meals',
    imageUrl: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=1200&q=80',
    rating: 4.6,
    eta: '25-35 min',
    deliveryFee: 45,
    isOpen: false,
  ),
  Restaurant(
    name: 'Mango Avenue',
    category: 'Desserts',
    imageUrl: 'https://images.unsplash.com/photo-1466978913421-dad2ebd01d17?auto=format&fit=crop&w=1200&q=80',
    rating: 4.5,
    eta: '10-15 min',
    deliveryFee: 15,
    isOpen: true,
  ),
];

const List<FoodItem> kFoods = [
  FoodItem(
    name: 'Spicy Burger Stack',
    restaurant: 'Burger Hub',
    imageUrl: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80',
    category: 'Burgers',
    description: 'Double beef patty, cheddar, lettuce, and spicy sauce.',
    price: 189,
    rating: 4.8,
    isPopular: true,
  ),
  FoodItem(
    name: 'Hawaiian Pizza',
    restaurant: 'Bistro 88',
    imageUrl: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=1200&q=80',
    category: 'Pizza',
    description: 'Ham, pineapple, mozzarella, and crispy crust.',
    price: 299,
    rating: 4.9,
    isPopular: true,
  ),
  FoodItem(
    name: 'Crispy Chicken Bucket',
    restaurant: 'Bistro 88',
    imageUrl: 'https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?auto=format&fit=crop&w=1200&q=80',
    category: 'Chicken',
    description: 'Tender fried chicken with garlic rice and dip.',
    price: 249,
    rating: 4.7,
    isPopular: true,
  ),
  FoodItem(
    name: 'Chicken Adobo Rice Bowl',
    restaurant: 'Aristocrat',
    imageUrl: 'https://images.unsplash.com/photo-1525351484163-7529414344d8?auto=format&fit=crop&w=1200&q=80',
    category: 'Rice Meals',
    description: 'Classic Filipino adobo with aromatic rice.',
    price: 185,
    rating: 4.8,
    isPopular: true,
  ),
  FoodItem(
    name: 'Creamy Carbonara',
    restaurant: 'Green Bowl',
    imageUrl: 'https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?auto=format&fit=crop&w=1200&q=80',
    category: 'Pasta',
    description: 'Creamy sauce with bacon, parmesan, and pasta.',
    price: 220,
    rating: 4.6,
    isPopular: false,
  ),
  FoodItem(
    name: 'Fresh Lemon Iced Tea',
    restaurant: 'Mango Avenue',
    imageUrl: 'https://images.unsplash.com/photo-1546173159-315724a31696?auto=format&fit=crop&w=1200&q=80',
    category: 'Drinks',
    description: 'Chilled, refreshing citrus beverage.',
    price: 95,
    rating: 4.5,
    isPopular: true,
  ),
  FoodItem(
    name: 'Classic Halo-Halo',
    restaurant: 'Mango Avenue',
    imageUrl: 'https://images.unsplash.com/photo-1551024601-bec78aea704b?auto=format&fit=crop&w=1200&q=80',
    category: 'Desserts',
    description: 'Shaved ice, leche flan, beans and fruit.',
    price: 135,
    rating: 4.7,
    isPopular: true,
  ),
  FoodItem(
    name: 'Cheesy Fries',
    restaurant: 'Burger Hub',
    imageUrl: 'https://images.unsplash.com/photo-1576101678438-7d2679f7de95?auto=format&fit=crop&w=1200&q=80',
    category: 'Snacks',
    description: 'Golden fries with melted cheese topping.',
    price: 120,
    rating: 4.5,
    isPopular: false,
  ),
];

class FoodAppState extends ChangeNotifier {
  SharedPreferences? _prefs;

  bool demoMode = true;
  bool ready = false;
  bool loggedIn = false;
  String? syncWarning;
  UserProfile user = UserProfile.empty();
  String selectedCategory = 'All';
  String searchQuery = '';
  double minimumPrice = 0;
  double maximumPrice = 1000;
  String foodSort = 'Popular';

  final List<Restaurant> restaurants = kRestaurants;
  final List<FoodItem> foods = kFoods;
  final Map<String, CartEntry> _cart = {};
  final Set<String> _favorites = {};
  final List<FoodOrder> _orders = [];

  List<CartEntry> get cartItems => List.unmodifiable(_cart.values);
  List<FoodOrder> get orders => List.unmodifiable(_orders);
  List<String> get favorites => List.unmodifiable(_favorites);
  int get cartCount => _cart.values.fold(0, (total, item) => total + item.quantity);
  double get cartSubtotal => _cart.values.fold(
    0,
    (total, item) => total + item.food.price * item.quantity,
  );
  double get cartDeliveryFee => _cart.isEmpty ? 0 : 35;
  double get cartTotal => cartSubtotal + cartDeliveryFee;

  Future<void> boot() async {
    final preferences = SharedPreferences.getInstance();
    await Future.wait<void>([
      Firebase.initializeApp()
          .timeout(const Duration(seconds: 2))
          .then<void>((_) => _firebaseAvailable = true)
          .catchError((Object _) => _firebaseAvailable = false),
      preferences
          .timeout(const Duration(seconds: 2))
          .then<void>((value) => _prefs = value)
          .catchError((Object _) => _prefs = null),
    ]);

    demoMode = !_firebaseAvailable;
    final remember = _prefs?.getBool('foodfind_remember_me') ?? false;
    final logged = _prefs?.getBool('foodfind_logged_in') ?? false;
    final email = _prefs?.getString('foodfind_user_email') ?? '';
    final name = _prefs?.getString('foodfind_user_name') ?? 'Foodie';
    final phone = _prefs?.getString('foodfind_user_phone') ?? '';
    final address = _prefs?.getString('foodfind_user_address') ?? '';

    _restoreList<CartEntry>(
      'foodfind_cart',
      (value) => CartEntry.fromJson(Map<String, dynamic>.from(value as Map)),
      (values) => _cart.addEntries(values.map((item) => MapEntry(item.food.name, item))),
    );
    _restoreList<String>(
      'foodfind_favorites',
      (value) => value as String,
      (values) => _favorites.addAll(values),
    );
    _restoreList<FoodOrder>(
      'foodfind_orders',
      (value) => FoodOrder.fromJson(Map<String, dynamic>.from(value as Map)),
      _orders.addAll,
    );

    if (demoMode) {
      final localDemoAccount =
          _prefs?.getBool('foodfind_demo_account') ?? false;
      if (remember && logged && email.isNotEmpty && localDemoAccount) {
        user = UserProfile(
          name: name,
          email: email,
          phone: phone,
          address: address,
        );
        loggedIn = true;
      }
    } else {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null && remember && logged) {
        user = UserProfile(
          name: firebaseUser.displayName ?? user.name,
          email: firebaseUser.email ?? user.email,
          phone: phone,
          address: address,
        );
        loggedIn = true;
        unawaited(_loadCloudData());
      } else if (firebaseUser != null && !remember) {
        unawaited(FirebaseAuth.instance.signOut());
      }
    }

    ready = true;
    notifyListeners();
  }

  void _restoreList<T>(
    String key,
    T Function(dynamic) decode,
    void Function(List<T>) assign,
  ) {
    try {
      final raw = _prefs?.getString(key);
      if (raw != null) assign((jsonDecode(raw) as List<dynamic>).map(decode).toList());
    } on FormatException {
      _prefs?.remove(key);
    } on TypeError {
      _prefs?.remove(key);
    }
  }

  Future<void> _saveList<T>(String key, Iterable<T> values, Object? Function(T) encode) async {
    await _prefs?.setString(key, jsonEncode(values.map(encode).toList()));
  }

  List<Restaurant> get filteredRestaurants {
    final query = searchQuery.toLowerCase();
    return restaurants.where((restaurant) {
      final matchesCategory =
          selectedCategory == 'All' || restaurant.category == selectedCategory;
      final matchesSearch =
          query.isEmpty ||
          restaurant.name.toLowerCase().contains(query) ||
          restaurant.category.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<FoodItem> get filteredFoods {
    final query = searchQuery.toLowerCase();
    final results = foods.where((food) {
      final matchesCategory =
          selectedCategory == 'All' || food.category == selectedCategory;
      final matchesPrice = food.price >= minimumPrice && food.price <= maximumPrice;
      final matchesSearch =
          query.isEmpty ||
          food.name.toLowerCase().contains(query) ||
          food.restaurant.toLowerCase().contains(query) ||
          food.description.toLowerCase().contains(query);
      return matchesCategory && matchesPrice && matchesSearch;
    }).toList();

    if (foodSort == 'Price: low to high') {
      results.sort((a, b) => a.price.compareTo(b.price));
    } else if (foodSort == 'Price: high to low') {
      results.sort((a, b) => b.price.compareTo(a.price));
    } else {
      results.sort((a, b) {
        final popularOrder = b.isPopular.toString().compareTo(a.isPopular.toString());
        return popularOrder != 0 ? popularOrder : b.rating.compareTo(a.rating);
      });
    }
    return results;
  }

  List<FoodItem> get categoryFoods => filteredFoods;

  void setPriceFilter(double minimum, double maximum) {
    minimumPrice = minimum;
    maximumPrice = maximum;
    notifyListeners();
  }

  void setFoodSort(String value) {
    foodSort = value;
    notifyListeners();
  }

  bool isFavorite(FoodItem food) => _favorites.contains(food.name);

  Future<void> toggleFavorite(FoodItem food) async {
    if (!_favorites.add(food.name)) _favorites.remove(food.name);
    await _saveList<String>('foodfind_favorites', _favorites, (value) => value);
    notifyListeners();
  }

  Future<void> addToCart(FoodItem food, {int quantity = 1}) async {
    final current = _cart[food.name]?.quantity ?? 0;
    _cart[food.name] = CartEntry(
      food: food,
      quantity: (current + quantity).clamp(1, 99).toInt(),
    );
    await _persistCart();
    notifyListeners();
  }

  Future<void> setCartQuantity(FoodItem food, int quantity) async {
    final entry = _cart[food.name];
    if (entry == null) return;
    _cart[food.name] = entry.copyWith(quantity: quantity.clamp(1, 99).toInt());
    await _persistCart();
    notifyListeners();
  }

  Future<void> removeFromCart(FoodItem food) async {
    _cart.remove(food.name);
    await _persistCart();
    notifyListeners();
  }

  Future<void> clearCart() async {
    _cart.clear();
    await _persistCart();
    notifyListeners();
  }

  Future<void> _persistCart() => _saveList<CartEntry>(
    'foodfind_cart',
    _cart.values,
    (entry) => entry.toJson(),
  );

  Future<void> updateProfile({
    required String name,
    required String phone,
    required String address,
  }) async {
    user = UserProfile(
      name: name.trim(),
      email: user.email,
      phone: phone.trim(),
      address: address.trim(),
    );
    await _prefs?.setString('foodfind_user_name', user.name);
    await _prefs?.setString('foodfind_user_phone', user.phone);
    await _prefs?.setString('foodfind_user_address', user.address);
    if (!demoMode) {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          await firebaseUser.updateDisplayName(user.name);
          await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .set({
                'name': user.name,
                'email': user.email,
                'phone': user.phone,
                'address': user.address,
              }, SetOptions(merge: true));
          syncWarning = null;
        } on FirebaseException catch (error) {
          syncWarning =
              'Profile saved on this device. Cloud sync failed: ${error.message}';
        }
      }
    }
    notifyListeners();
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    if (newPassword.length < 6) return 'Password must be at least 6 characters.';
    if (newPassword != confirmation) return 'Passwords do not match.';
    if (demoMode) {
      final stored = _prefs?.getString('foodfind_user_password') ?? '';
      if (stored != currentPassword) return 'Current password is incorrect.';
      await _prefs?.setString('foodfind_user_password', newPassword);
      return null;
    }

    try {
      await FirebaseAuth.instance.currentUser?.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (error) {
      return error.message ?? 'Unable to change password.';
    }
  }

  Future<FoodOrder?> placeOrder({
    required String customerName,
    required String phone,
    required String address,
    required String paymentMethod,
  }) async {
    if (_cart.isEmpty) return null;
    final now = DateTime.now();
    final order = FoodOrder(
      reference: 'FF-${now.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      createdAt: now,
      customerName: customerName.trim(),
      phone: phone.trim(),
      address: address.trim(),
      paymentMethod: paymentMethod,
      items: List.unmodifiable(_cart.values),
      subtotal: cartSubtotal,
      deliveryFee: cartDeliveryFee,
      statusIndex: 0,
    );
    _orders.insert(0, order);
    _cart.clear();
    await _persistCart();
    await _saveList<FoodOrder>('foodfind_orders', _orders, (value) => value.toJson());
    await _saveCloudOrder(order);
    notifyListeners();
    return order;
  }

  Future<void> _saveCloudOrder(FoodOrder order) async {
    if (demoMode) return;
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('orders')
          .doc(order.reference)
          .set(order.toJson());
      syncWarning = null;
    } on FirebaseException catch (error) {
      syncWarning = 'Order saved on this device. Cloud sync failed: ${error.message}';
    }
  }

  Future<void> _loadCloudData() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('orders')
          .get()
          .timeout(const Duration(seconds: 4));
      if (snapshot.docs.isNotEmpty) {
        _orders
          ..clear()
          ..addAll(snapshot.docs.map((doc) => FoodOrder.fromJson(doc.data())));
        await _saveList<FoodOrder>('foodfind_orders', _orders, (value) => value.toJson());
        notifyListeners();
      }
    } on TimeoutException {
      syncWarning = 'Showing saved orders. Cloud sync timed out.';
    } on FirebaseException catch (error) {
      syncWarning = 'Showing saved orders. Cloud sync failed: ${error.message}';
    }
  }

  Future<void> advanceDemoOrder(FoodOrder order) async {
    if (!demoMode || order.statusIndex >= kOrderStatuses.length - 1) return;
    final index = _orders.indexWhere((item) => item.reference == order.reference);
    if (index == -1) return;
    _orders[index] = order.copyWith(statusIndex: order.statusIndex + 1);
    await _saveList<FoodOrder>('foodfind_orders', _orders, (value) => value.toJson());
    notifyListeners();
  }

  Future<void> reorder(FoodOrder order) async {
    for (final item in order.items) {
      final current = _cart[item.food.name]?.quantity ?? 0;
      _cart[item.food.name] = CartEntry(
        food: item.food,
        quantity: (current + item.quantity).clamp(1, 99).toInt(),
      );
    }
    await _persistCart();
    notifyListeners();
  }

  Future<String?> signIn({
    required String email,
    required String password,
    bool remember = true,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      return 'Please fill in all fields.';
    }
    if (!_validEmail(email)) return 'Enter a valid email address.';

    if (demoMode) {
      final storedEmail = _prefs?.getString('foodfind_user_email') ?? '';
      final storedPassword = _prefs?.getString('foodfind_user_password') ?? '';
      final storedName = _prefs?.getString('foodfind_user_name') ?? 'Foodie';

      if (storedEmail.isEmpty || storedPassword.isEmpty) {
        return 'No account found. Please create one.';
      }
      if (storedEmail.toLowerCase() != email.trim().toLowerCase()) {
        return 'Account not found for this email.';
      }
      if (storedPassword != password) {
        return 'Incorrect password. Please try again.';
      }

      user = UserProfile(
        name: storedName,
        email: storedEmail,
        phone: _prefs?.getString('foodfind_user_phone') ?? '',
        address: _prefs?.getString('foodfind_user_address') ?? '',
      );
      loggedIn = true;
      await _prefs?.setBool('foodfind_demo_account', false);
      await _prefs?.setBool('foodfind_remember_me', remember);
      await _prefs?.setBool('foodfind_logged_in', true);
      await _prefs?.setString('foodfind_user_name', storedName);
      notifyListeners();
      return null;
    }

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      user = UserProfile(
        name: credential.user?.displayName ?? 'Foodie',
        email: credential.user?.email ?? email.trim(),
      );
      loggedIn = true;
      await _prefs?.setBool('foodfind_remember_me', remember);
      await _prefs?.setBool('foodfind_logged_in', true);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (error) {
      return error.message ?? 'Unable to sign in.';
    } on FirebaseException catch (error) {
      return error.message ?? 'Authentication service is unavailable.';
    }
  }

  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required String confirm,
  }) async {
    if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      return 'Please complete all fields.';
    }
    if (!_validEmail(email)) return 'Enter a valid email address.';
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (password != confirm) {
      return 'Passwords do not match.';
    }

    if (demoMode) {
      final trimmedName = name.trim();
      final trimmedEmail = email.trim().toLowerCase();
      await _prefs?.setString('foodfind_user_name', trimmedName);
      await _prefs?.setString('foodfind_user_email', trimmedEmail);
      await _prefs?.setString('foodfind_user_password', password);
      await _prefs?.setBool('foodfind_demo_account', true);
      await _prefs?.setBool('foodfind_remember_me', true);
      await _prefs?.setBool('foodfind_logged_in', true);

      user = UserProfile(name: trimmedName, email: trimmedEmail);
      loggedIn = true;
      notifyListeners();
      return null;
    }

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      await credential.user?.updateDisplayName(name.trim());
      user = UserProfile(name: name.trim(), email: email.trim());
      loggedIn = true;
      await _prefs?.setBool('foodfind_demo_account', false);
      await _prefs?.setBool('foodfind_remember_me', true);
      await _prefs?.setBool('foodfind_logged_in', true);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (error) {
      return error.message ?? 'Unable to create account.';
    } on FirebaseException catch (error) {
      return error.message ?? 'Authentication service is unavailable.';
    }
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  Future<String> resetPassword(String email) async {
    if (email.trim().isEmpty) {
      return 'Please enter your email address.';
    }
    if (!_validEmail(email)) return 'Enter a valid email address.';
    if (demoMode) {
      return 'Password reset is unavailable in demo mode. Configure Firebase to send a reset email.';
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return 'Password reset email sent to ${email.trim()}.';
    } on FirebaseAuthException catch (error) {
      return error.message ?? 'Unable to reset password.';
    }
  }

  Future<void> logout() async {
    if (!demoMode) {
      try {
        await FirebaseAuth.instance.signOut();
      } on FirebaseException catch (error) {
        syncWarning =
            'Signed out locally. Firebase sign-out failed: ${error.message}';
      }
    }
    loggedIn = false;
    user = UserProfile.empty();
    await _prefs?.setBool('foodfind_logged_in', false);
    await _prefs?.setBool('foodfind_remember_me', false);
    notifyListeners();
  }

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void setCategory(String value) {
    selectedCategory = value;
    notifyListeners();
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final FoodAppState _state;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  bool _minimumDurationPassed = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _state = context.read<FoodAppState>();
    _state.addListener(_openApp);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _minimumDurationPassed = true);
      _openApp();
    });
  }

  void _openApp() {
    if (!mounted || !_state.ready || !_minimumDurationPassed) return;

    _state.removeListener(_openApp);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            _state.loggedIn ? const MainShell() : const WelcomeScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _state.removeListener(_openApp);
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28),
                  child: FoodFindBrand(
                    markSize: 132,
                    titleSize: 34,
                    showTagline: true,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
                const FoodFindMark(size: 96),
              const SizedBox(height: 24),
              Text(
                'Welcome to FoodFind',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Fresh meals, fast delivery, and local favorites delivered in minutes.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: elevatedButton(AppColors.primary),
                  child: const Text('Login'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  style: outlinedButton(AppColors.secondary),
                  child: const Text('Create account'),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _rememberMe = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: FoodFindMark(size: 64)),
                const SizedBox(height: 18),
                Text(
                  'Welcome back!',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sign in to continue ordering your favorite meals.',
                  style: GoogleFonts.poppins(color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                AppTextField(
                  label: 'Email',
                  controller: _emailController,
                  icon: Icons.email_outlined,
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Enter your email'
                      : null,
                ),
                const SizedBox(height: 18),
                AppTextField(
                  label: 'Password',
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  obscureText: !_showPassword,
                  suffix: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                  validator: (value) => (value == null || value.length < 6)
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      activeColor: AppColors.primary,
                      onChanged: (value) =>
                          setState(() => _rememberMe = value ?? true),
                    ),
                    const Text('Remember me'),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: const Text('Forgot password?'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitLogin,
                    style: elevatedButton(AppColors.primary),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Login'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('New here? '),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final error = await context.read<FoodAppState>().signIn(
      email: _emailController.text,
      password: _passwordController.text,
      remember: _rememberMe,
    );
    setState(() => _submitting = false);

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showPassword = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: FoodFindMark(size: 64)),
                const SizedBox(height: 18),
                Text(
                  'Join FoodFind',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Create your account and order in a few taps.',
                  style: GoogleFonts.poppins(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                AppTextField(
                  label: 'Full name',
                  controller: _nameController,
                  icon: Icons.person_outline_rounded,
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Email',
                  controller: _emailController,
                  icon: Icons.email_outlined,
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Enter your email'
                      : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Password',
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  obscureText: !_showPassword,
                  suffix: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                  validator: (value) => (value == null || value.length < 6)
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Confirm password',
                  controller: _confirmController,
                  icon: Icons.lock_outline_rounded,
                  obscureText: !_showPassword,
                  validator: (value) => value != _passwordController.text
                      ? 'Passwords do not match'
                      : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitRegister,
                    style: elevatedButton(AppColors.primary),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create my account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final error = await context.read<FoodAppState>().register(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      confirm: _confirmController.text,
    );
    setState(() => _submitting = false);

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Reset your password',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Enter your email and we will help you recover your account.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Email',
                controller: _emailController,
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _sendReset,
                  style: elevatedButton(AppColors.primary),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send reset link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendReset() async {
    setState(() => _submitting = true);
    final message = await context.read<FoodAppState>().resetPassword(
      _emailController.text,
    );
    setState(() => _submitting = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.secondary),
    );

    if (message.startsWith('Password reset email sent')) {
      Navigator.pop(context);
    }
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          RestaurantScreen(),
          CartScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();
    final firstName = state.user.name.split(' ').first;
    final popularFoods = state.filteredFoods
        .where((food) => food.isPopular || food.rating >= 4.6)
        .toList();
    final bestSellers = state.filteredFoods
      .where((food) => food.isPopular)
      .toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FoodFindMark(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FoodFind',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        'Hello, $firstName',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open cart',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  ),
                  icon: Badge(
                    label: Text('${state.cartCount}'),
                    isLabelVisible: state.cartCount > 0,
                    child: const Icon(Icons.shopping_bag_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              onChanged: state.setSearch,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card,
                hintText: 'Search food and restaurants',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Deliver to',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.user.address.isEmpty
                              ? 'Add your delivery address'
                              : state.user.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FoodFind picks',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Explore local favorites, ready to order.',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Categories',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kCategories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = kCategories[index];
                  final selected = state.selectedCategory == category;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    labelStyle: GoogleFonts.poppins(
                      color: selected ? AppColors.primary : AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => state.setCategory(category),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Popular restaurants',
              onPressed: () => _openExplore(context, restaurants: true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.restaurants.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  return RestaurantCard(restaurant: state.restaurants[index]);
                },
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Recommended food',
              onPressed: () => _openFoodCatalog(context),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: popularFoods.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  return FoodCard(food: popularFoods[index]);
                },
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              title: 'Best sellers',
              onPressed: () => _openFoodCatalog(context),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bestSellers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  return FoodCard(food: bestSellers[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openExplore(BuildContext context, {bool restaurants = false}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RestaurantScreen(showRestaurants: restaurants),
    ),
  );
}

void _openFoodCatalog(BuildContext context) => _openExplore(context);

class RestaurantScreen extends StatefulWidget {
  const RestaurantScreen({super.key, this.showRestaurants = false});

  final bool showRestaurants;

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  late bool _showRestaurants;

  @override
  void initState() {
    super.initState();
    _showRestaurants = widget.showRestaurants;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Explore',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (!_showRestaurants)
                  IconButton(
                    tooltip: 'Filter by price',
                    onPressed: () => _showPriceFilter(context, state),
                    icon: const Icon(Icons.filter_list_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: state.setSearch,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card,
                hintText: _showRestaurants
                  ? 'Search restaurants'
                  : 'Search food and restaurants',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Foods')),
                ButtonSegment(value: true, label: Text('Restaurants')),
              ],
              selected: {_showRestaurants},
              onSelectionChanged: (selection) {
                setState(() => _showRestaurants = selection.first);
              },
            ),
            if (!_showRestaurants) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: state.foodSort,
                      decoration: const InputDecoration(
                        labelText: 'Sort foods',
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.card,
                      ),
                      items: const [
                        'Popular',
                        'Price: low to high',
                        'Price: high to low',
                      ].map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) state.setFoodSort(value);
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: kCategories.map((category) {
                    final selected = state.selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: selected,
                        onSelected: (_) => state.setCategory(category),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _showRestaurants
                  ? _restaurantResults(state)
                  : _foodResults(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _restaurantResults(FoodAppState state) {
    final restaurants = state.filteredRestaurants;
    if (restaurants.isEmpty) return const _EmptyState(message: 'No restaurants found.');
    return ListView.separated(
      itemCount: restaurants.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) => RestaurantListCard(
        restaurant: restaurants[index],
      ),
    );
  }

  Widget _foodResults(FoodAppState state) {
    final foods = state.filteredFoods;
    if (foods.isEmpty) return const _EmptyState(message: 'No food matches your search.');
    return ListView.separated(
      itemCount: foods.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => FoodListTile(food: foods[index]),
    );
  }

  Future<void> _showPriceFilter(
    BuildContext context,
    FoodAppState state,
  ) async {
    var values = RangeValues(state.minimumPrice, state.maximumPrice);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Price range: ${formatPrice(values.start)} - ${formatPrice(values.end)}'),
                RangeSlider(
                  min: 0,
                  max: 1000,
                  divisions: 20,
                  values: values,
                  onChanged: (value) => setModalState(() => values = value),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      state.setPriceFilter(values.start, values.end);
                      Navigator.pop(context);
                    },
                    child: const Text('Apply filter'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
            Text(
              'Profile',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.user.name,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          state.user.email.isEmpty
                              ? 'Demo user'
                              : state.user.email,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _ProfileRow(
              icon: Icons.location_on_outlined,
              title: 'Delivery address',
              subtitle: state.user.address.isEmpty
                  ? 'Add a delivery address'
                  : state.user.address,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              ),
            ),
            _ProfileRow(
              icon: Icons.payment_rounded,
              title: 'Payment method',
              subtitle: 'Selected during checkout',
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Payment methods'),
                  content: Text(
                    state.demoMode
                        ? 'Cash on Delivery is available. GCash and Maya are simulated only; no payment is processed.'
                        : 'Choose Cash on Delivery, GCash, or Maya during checkout. Wallet payments require an enabled payment gateway.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ],
                ),
              ),
            ),
            if (state.demoMode)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Demo mode • account and order data stay on this device.'),
              ),
            _ProfileRow(
              icon: Icons.receipt_long_outlined,
              title: 'Order history',
              subtitle: '${state.orders.length} orders',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
              ),
            ),
            _ProfileRow(
              icon: Icons.edit_location_alt_outlined,
              title: 'Edit profile',
              subtitle: 'Name, phone number, and address',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              ),
            ),
            _ProfileRow(
              icon: Icons.favorite_border_rounded,
              title: 'Saved favorites',
              subtitle: '${state.favorites.length} food items',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              ),
            ),
            _ProfileRow(
              icon: Icons.lock_outline_rounded,
              title: 'Change password',
              subtitle: 'Update your sign-in password',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              ),
            ),
            _ProfileRow(
              icon: Icons.info_outline_rounded,
              title: 'Account information',
              subtitle: 'View account and payment details',
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Account information'),
                  content: Text('${state.user.email}\n${state.demoMode ? 'Local demo account' : 'Firebase account'}\nPayments are selected at checkout.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final logout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Log out?'),
                      content: const Text('You can sign in again to access your account.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
                      ],
                    ),
                  );
                  if (logout != true || !context.mounted) return;
                  await context.read<FoodAppState>().logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                      (route) => false,
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Logout'),
              ),
            ),
        ],
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();
    final foods = state.foods.where(state.isFavorite).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Saved favorites')),
      body: foods.isEmpty
          ? const _EmptyState(message: 'Save a food item to find it here later.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: foods.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) => FoodListTile(food: foods[index]),
            ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    final user = context.read<FoodAppState>().user;
    _nameController = TextEditingController(text: user.name == 'Guest' ? '' : user.name);
    _phoneController = TextEditingController(text: user.phone);
    _addressController = TextEditingController(text: user.address);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit profile')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (value) => value == null || value.trim().isEmpty ? 'Enter your name.' : null,
          ),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Contact number'),
          ),
          TextFormField(
            controller: _addressController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Delivery address'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _save,
            child: const Text('Save profile'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<FoodAppState>().updateProfile(
      name: _nameController.text,
      phone: _phoneController.text,
      address: _addressController.text,
    );
    if (mounted) Navigator.pop(context);
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPasswords = false;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Change password')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final field in [
          ('Current password', _current),
          ('New password', _next),
          ('Confirm new password', _confirm),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              controller: field.$2,
              obscureText: !_showPasswords,
              decoration: InputDecoration(labelText: field.$1),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show passwords'),
          value: _showPasswords,
          onChanged: (value) => setState(() => _showPasswords = value),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _saving ? null : _changePassword,
          child: _saving ? const CircularProgressIndicator() : const Text('Update password'),
        ),
      ],
    ),
  );

  Future<void> _changePassword() async {
    setState(() => _saving = true);
    final message = await context.read<FoodAppState>().changePassword(
      currentPassword: _current.text,
      newPassword: _next.text,
      confirmation: _confirm.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated.')));
    Navigator.pop(context);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.restaurant_outlined, size: 42, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class FoodListTile extends StatelessWidget {
  const FoodListTile({required this.food, super.key});

  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FoodDetailsScreen(food: food)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FoodFindImage(
                  url: food.imageUrl,
                  width: 82,
                  height: 82,
                  icon: Icons.fastfood_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(food.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(food.restaurant, style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 6),
                    Text(formatPrice(food.price),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
              ),
              IconButton(
                tooltip: state.isFavorite(food)
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: () => state.toggleFavorite(food),
                icon: Icon(
                  state.isFavorite(food) ? Icons.favorite : Icons.favorite_border,
                  color: state.isFavorite(food) ? AppColors.error : AppColors.muted,
                ),
              ),
              IconButton(
                tooltip: 'Add to cart',
                onPressed: () async {
                  await state.addToCart(food);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${food.name} added to cart.')),
                    );
                  }
                },
                icon: const Icon(Icons.add_shopping_cart_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          if (state.cartItems.isNotEmpty)
            IconButton(
              tooltip: 'Clear cart',
              onPressed: () => _confirmClear(context, state),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: state.cartItems.isEmpty
          ? const _EmptyState(message: 'Your cart is empty.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.cartItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = state.cartItems[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.food.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(formatPrice(item.food.price), style: const TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Decrease quantity',
                        onPressed: () => state.setCartQuantity(item.food, item.quantity - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: 'Increase quantity',
                        onPressed: () => state.setCartQuantity(item.food, item.quantity + 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: () => state.removeFromCart(item.food),
                        icon: const Icon(Icons.close_rounded, color: AppColors.error),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: state.cartItems.isEmpty
          ? SafeArea(
              minimum: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RestaurantScreen()),
                ),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Browse food'),
              ),
            )
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PriceRow(label: 'Subtotal', amount: state.cartSubtotal),
                  _PriceRow(label: 'Delivery fee', amount: state.cartDeliveryFee),
                  const Divider(),
                  _PriceRow(label: 'Total', amount: state.cartTotal, bold: true),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                      ),
                      child: const Text('Continue to checkout'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, FoodAppState state) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('All items will be removed from your cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep items')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear cart')),
        ],
      ),
    );
    if (clear == true) await state.clearCart();
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.amount, this.bold = false});

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
        Text(formatPrice(amount), style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
      ],
    ),
  );
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  String _paymentMethod = 'Cash on Delivery';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<FoodAppState>().user;
    _nameController = TextEditingController(text: user.name == 'Guest' ? '' : user.name);
    _phoneController = TextEditingController(text: user.phone);
    _addressController = TextEditingController(text: user.address);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Delivery details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _CheckoutField(controller: _nameController, label: 'Customer name', validator: _required),
            const SizedBox(height: 12),
            _CheckoutField(
              controller: _phoneController,
              label: 'Contact number',
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || !RegExp(r'^\+?[0-9][0-9\s-]{8,14}$').hasMatch(value.trim())) {
                  return 'Enter a valid contact number.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _CheckoutField(
              controller: _addressController,
              label: 'Delivery address',
              maxLines: 2,
              validator: (value) => value == null || value.trim().length < 8
                  ? 'Enter a complete delivery address.'
                  : null,
            ),
            const SizedBox(height: 22),
            Text('Payment method', style: Theme.of(context).textTheme.titleLarge),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: [
                const DropdownMenuItem(
                  value: 'Cash on Delivery',
                  child: Text('Cash on Delivery (COD)'),
                ),
                DropdownMenuItem(
                  value: 'GCash',
                  child: Text('GCash${state.demoMode ? ' (simulated)' : ''}'),
                ),
                DropdownMenuItem(
                  value: 'Maya',
                  child: Text('Maya${state.demoMode ? ' (simulated)' : ''}'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            if (state.demoMode && _paymentMethod != 'Cash on Delivery')
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Demo payment only. No money is charged and no payment is processed.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            const Divider(height: 28),
            Text('Order summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...state.cartItems.map((item) => _PriceRow(
              label: '${item.quantity} × ${item.food.name}',
              amount: item.food.price * item.quantity,
            )),
            const Divider(height: 24),
            _PriceRow(label: 'Subtotal', amount: state.cartSubtotal),
            _PriceRow(label: 'Delivery fee', amount: state.cartDeliveryFee),
            _PriceRow(label: 'Total', amount: state.cartTotal, bold: true),
            if (state.demoMode)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Demo mode: this order will be saved on this device.'),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting || state.cartItems.isEmpty ? null : _placeOrder,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Place order'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'This field is required.'
      : null;

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final state = context.read<FoodAppState>();
    await state.updateProfile(
      name: _nameController.text,
      phone: _phoneController.text,
      address: _addressController.text,
    );
    final order = await state.placeOrder(
      customerName: _nameController.text,
      phone: _phoneController.text,
      address: _addressController.text,
      paymentMethod: _paymentMethod,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your cart is empty.')),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => OrderTrackingScreen(order: order, showConfirmation: true)),
    );
  }
}

class _CheckoutField extends StatelessWidget {
  const _CheckoutField({
    required this.controller,
    required this.label,
    required this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    keyboardType: keyboardType,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label, filled: true, fillColor: AppColors.card),
  );
}

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<FoodAppState>().orders;
    return Scaffold(
      appBar: AppBar(title: const Text('Order history')),
      body: orders.isEmpty
          ? const _EmptyState(message: 'Your previous orders will appear here.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _OrderHistoryTile(order: orders[index]),
            ),
    );
  }
}

class _OrderHistoryTile extends StatelessWidget {
  const _OrderHistoryTile({required this.order});

  final FoodOrder order;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.reference, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${order.createdAt.toLocal()}'.split('.').first, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 6),
        Text(order.items.map((item) => '${item.quantity} × ${item.food.name}').join(', ')),
        const SizedBox(height: 6),
        Text('${formatPrice(order.total)} • ${order.paymentMethod} • ${order.status}'),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => OrderTrackingScreen(order: order)),
              ),
              child: const Text('View order'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await context.read<FoodAppState>().reorder(order);
                if (context.mounted) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen()));
                }
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Reorder'),
            ),
          ],
        ),
      ],
    ),
  );
}

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({required this.order, this.showConfirmation = false, super.key});

  final FoodOrder order;
  final bool showConfirmation;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodAppState>();
    final current = state.orders.where((item) => item.reference == order.reference).firstOrNull ?? order;
    return Scaffold(
      appBar: AppBar(title: Text(showConfirmation ? 'Order confirmed' : 'Track order')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (showConfirmation) ...[
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 58),
            const SizedBox(height: 10),
            Text('Order placed', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          ],
          Text('Reference: ${current.reference}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${current.createdAt.toLocal()}'.split('.').first),
          const SizedBox(height: 8),
          Text('Delivering to ${current.address}'),
          Text('Payment: ${current.paymentMethod}${state.demoMode && current.paymentMethod != 'Cash on Delivery' ? ' (simulated)' : ''}'),
          const SizedBox(height: 10),
          ...current.items.map((item) => _PriceRow(
            label: '${item.quantity} × ${item.food.name}',
            amount: item.food.price * item.quantity,
          )),
          const Divider(height: 24),
          _PriceRow(label: 'Total', amount: current.total, bold: true),
          const SizedBox(height: 18),
          Text('Order status', style: Theme.of(context).textTheme.titleLarge),
          ...List.generate(kOrderStatuses.length, (index) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              index <= current.statusIndex ? Icons.check_circle : Icons.radio_button_unchecked,
              color: index <= current.statusIndex ? AppColors.success : AppColors.muted,
            ),
            title: Text(kOrderStatuses[index]),
          )),
          if (state.demoMode && current.statusIndex < kOrderStatuses.length - 1)
            OutlinedButton.icon(
              onPressed: () => state.advanceDemoOrder(current),
              icon: const Icon(Icons.update_rounded),
              label: const Text('Simulate next demo status'),
            ),
          if (state.syncWarning != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(state.syncWarning!)),
          if (showConfirmation)
            TextButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainShell()),
                (route) => false,
              ),
              child: const Text('Continue shopping'),
            ),
        ],
      ),
    );
  }
}

class FoodCard extends StatelessWidget {
  const FoodCard({required this.food, super.key});

  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => FoodDetailsScreen(food: food))),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FoodFindImage(
                url: food.imageUrl,
                width: double.infinity,
                height: 88,
                icon: Icons.fastfood_rounded,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              food.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              food.restaurant,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  food.rating.toStringAsFixed(1),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  formatPrice(food.price),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                IconButton(
                  tooltip: 'Add to cart',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                  onPressed: () => context.read<FoodAppState>().addToCart(food),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 19),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({required this.restaurant, super.key});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RestaurantDetailScreen(restaurant: restaurant),
        ),
      ),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FoodFindImage(
                url: restaurant.imageUrl,
                width: double.infinity,
                height: 96,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              restaurant.name,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              restaurant.category,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  restaurant.rating.toStringAsFixed(1),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  restaurant.eta,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RestaurantListCard extends StatelessWidget {
  const RestaurantListCard({required this.restaurant, super.key});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RestaurantDetailScreen(restaurant: restaurant),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FoodFindImage(
                url: restaurant.imageUrl,
                width: 100,
                height: 100,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    restaurant.category,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        restaurant.rating.toStringAsFixed(1),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: restaurant.isOpen
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          restaurant.isOpen ? 'Open' : 'Closed',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: restaurant.isOpen
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Delivery fee: ${formatPrice(restaurant.deliveryFee)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RestaurantDetailScreen extends StatelessWidget {
  const RestaurantDetailScreen({required this.restaurant, super.key});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final items = context
        .watch<FoodAppState>()
        .foods
        .where((food) => food.restaurant == restaurant.name)
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: FoodFindImage(url: restaurant.imageUrl),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: restaurant.isOpen
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          restaurant.isOpen ? 'Open now' : 'Closed',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: restaurant.isOpen
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text(
                        '${restaurant.rating.toStringAsFixed(1)} rating',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.motorcycle_rounded,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        restaurant.eta,
                        style: GoogleFonts.poppins(color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Popular items',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...items.map((food) {
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FoodDetailsScreen(food: food),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FoodFindImage(
                                url: food.imageUrl,
                                width: 90,
                                height: 90,
                                icon: Icons.fastfood_rounded,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    food.name,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    food.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    formatPrice(food.price),
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FoodDetailsScreen extends StatefulWidget {
  const FoodDetailsScreen({required this.food, super.key});

  final FoodItem food;

  @override
  State<FoodDetailsScreen> createState() => _FoodDetailsScreenState();
}

class _FoodDetailsScreenState extends State<FoodDetailsScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final state = context.watch<FoodAppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food details'),
        actions: [
          IconButton(
            tooltip: state.isFavorite(food) ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => state.toggleFavorite(food),
            icon: Icon(
              state.isFavorite(food) ? Icons.favorite : Icons.favorite_border,
              color: state.isFavorite(food) ? AppColors.error : null,
            ),
          ),
          IconButton(
            tooltip: 'Open cart',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartScreen()),
            ),
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  FoodFindImage(
                    url: food.imageUrl,
                    width: double.infinity,
                    height: 300,
                    icon: Icons.fastfood_rounded,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      style: GoogleFonts.poppins(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        final restaurant = state.restaurants
                            .where((item) => item.name == food.restaurant)
                            .firstOrNull;
                        if (restaurant != null) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RestaurantDetailScreen(restaurant: restaurant),
                          ));
                        }
                      },
                      icon: const Icon(Icons.storefront_outlined, size: 18),
                      label: Text(food.restaurant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          food.rating.toStringAsFixed(1),
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            food.category,
                            style: GoogleFonts.poppins(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Description',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      food.description,
                      style: GoogleFonts.poppins(
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total price',
                              style: GoogleFonts.poppins(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              formatPrice(food.price * _quantity),
                              style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Decrease quantity',
                              onPressed: _quantity > 1
                                  ? () => setState(() => _quantity--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              tooltip: 'Increase quantity',
                              onPressed: _quantity < 99
                                  ? () => setState(() => _quantity++)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await state.addToCart(food, quantity: _quantity);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$_quantity × ${food.name} added to cart.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Add to cart'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        TextButton(onPressed: onPressed, child: const Text('See all')),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: AppColors.muted,
          ),
        ],
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.validator,
    this.obscureText = false,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? Function(String?)? validator;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      decoration: InputDecoration(
        fillColor: AppColors.card,
        filled: true,
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

ButtonStyle elevatedButton(Color color) {
  return ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

ButtonStyle outlinedButton(Color color) {
  return OutlinedButton.styleFrom(
    foregroundColor: color,
    side: BorderSide(color: color, width: 1.2),
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}
