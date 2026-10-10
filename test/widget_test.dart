// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:esprezzo/main.dart';

void main() {
  testWidgets('Product search displays results', (WidgetTester tester) async {
    await tester.pumpWidget(const ProductSearchApp());

    // Enter a search query
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'cola');

    // Tap the search icon
    final searchButton = find.byIcon(Icons.search);
    expect(searchButton, findsOneWidget);
    await tester.tap(searchButton);

    // Wait for the results to load
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Check that at least one product card is displayed
    final cardFinder = find.byType(Card);
    expect(cardFinder, findsWidgets);

    // Verify that at least one product card contains text matching the query
    final colaTextInCards = find.descendant(
      of: cardFinder,
      matching: find.textContaining('cola', findRichText: true),
    );
    expect(colaTextInCards, findsWidgets);
  });
}
