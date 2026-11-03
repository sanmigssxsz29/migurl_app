import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migurl_app/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('splash opens welcome screen when app state becomes ready', (
    tester,
  ) async {
    final state = FoodAppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SplashScreen()),
      ),
    );

    expect(find.text('FoodFind'), findsOneWidget);

    state.ready = true;
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Welcome to FoodFind'), findsOneWidget);
  });

  testWidgets('splash branding remains visible for two seconds', (tester) async {
    final state = FoodAppState()..ready = true;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SplashScreen()),
      ),
    );

    expect(find.text('Discover Food. Order Easily. Enjoy Every Bite.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.text('Discover Food. Order Easily. Enjoy Every Bite.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to FoodFind'), findsOneWidget);
  });

  test('cart totals, quantity limits, checkout, and saved data work', () async {
    SharedPreferences.setMockInitialValues({});
    final state = FoodAppState();
    await state.boot();
    final food = kFoods.first;

    await state.addToCart(food, quantity: 2);
    expect(state.cartCount, 2);
    expect(state.cartSubtotal, 378);
    expect(state.cartDeliveryFee, 35);
    expect(state.cartTotal, 413);

    await state.setCartQuantity(food, 0);
    expect(state.cartItems.single.quantity, 1);
    await state.toggleFavorite(food);

    final order = await state.placeOrder(
      customerName: 'Test User',
      phone: '09171234567',
      address: 'Quezon City, Metro Manila',
      paymentMethod: 'Cash on Delivery',
    );
    expect(order, isNotNull);
    expect(order!.reference, startsWith('FF-'));
    expect(order.total, 224);
    expect(state.cartItems, isEmpty);

    final restored = FoodAppState();
    await restored.boot();
    expect(restored.favorites, contains(food.name));
    expect(restored.orders.single.reference, order.reference);
    expect(restored.orders.single.items.single.quantity, 1);
  });

  test('food search, category, price, and sort filters update results', () {
    final state = FoodAppState();
    state.setPriceFilter(100, 200);
    state.setFoodSort('Price: low to high');
    expect(state.filteredFoods.every((food) => food.price >= 100 && food.price <= 200), isTrue);
    expect(state.filteredFoods.first.price, lessThanOrEqualTo(state.filteredFoods.last.price));

    state.setPriceFilter(0, 400);
    state.setCategory('Pizza');
    expect(state.filteredFoods.every((food) => food.category == 'Pizza'), isTrue);
    state.setSearch('hawaiian');
    expect(state.filteredFoods.map((food) => food.name), ['Hawaiian Pizza']);
  });
}
