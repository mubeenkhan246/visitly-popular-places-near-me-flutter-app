import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:most_visited_places/main.dart';

void main() {
  testWidgets('Visitly launches the map-first experience', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(const ProviderScope(child: VisitlyApp()));
    await tester.pump();

    expect(find.text('Search attractions, food, cities'), findsOneWidget);
    expect(find.text('Attractions'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });

  testWidgets('Explore place cards open the detail sheet', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeTabProvider.overrideWith((ref) => 1),
          currentLocationProvider.overrideWith((ref) => visitlyCenter),
          nearbyPlacesProvider.overrideWith(
            (ref) async => samplePlaces.take(4).toList(),
          ),
        ],
        child: const VisitlyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final tileTopLeft = tester.getTopLeft(find.byType(PlaceTile).first);
    await tester.tapAt(tileTopLeft + const Offset(40, 40));
    await tester.pumpAndSettle();

    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Add to trip'), findsOneWidget);
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });

  testWidgets('Saved and trip pages use selected places only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeTabProvider.overrideWith((ref) => 3),
          currentLocationProvider.overrideWith((ref) => visitlyCenter),
          nearbyPlacesProvider.overrideWith(
            (ref) async => samplePlaces.take(4).toList(),
          ),
          favoritePlacesProvider.overrideWith(
            (ref) => {'Old City Food Street'},
          ),
          tripPlacesProvider.overrideWith((ref) => {'Emerald Lake Viewpoint'}),
        ],
        child: const VisitlyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Old City Food Street'), findsOneWidget);
    expect(find.text('Royal Fort Gardens'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(VisitlyApp)),
    );
    container.read(activeTabProvider.notifier).state = 2;
    await tester.pumpAndSettle();

    expect(find.text('Emerald Lake Viewpoint'), findsOneWidget);
    expect(find.text('Old City Food Street'), findsNothing);
  });
}
