import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const ProviderScope(child: VisitlyApp()));
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const VisitlyShell()),
    ],
  );
});

final selectedRadiusProvider = StateProvider<int>((ref) => 5000);
final selectedCategoryProvider = StateProvider<String>((ref) => 'All');
final heatmapEnabledProvider = StateProvider<bool>((ref) => true);
final mapTypeProvider = StateProvider<MapType>((ref) => MapType.normal);
final selectedPlaceProvider = StateProvider<Place?>((ref) => null);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);
final activeTabProvider = StateProvider<int>((ref) => 0);
final favoritePlacesProvider = StateProvider<Set<String>>((ref) => <String>{});
final tripPlacesProvider = StateProvider<Set<String>>((ref) => <String>{});
final currentLocationProvider = StateProvider<LatLng?>((ref) => null);
final routeDestinationProvider = StateProvider<Place?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
final activeExploreFiltersProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);
const placesApiKey = String.fromEnvironment('MAPS_API_KEY');

final nearbyPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final currentLocation = ref.watch(currentLocationProvider);
  final radius = ref.watch(selectedRadiusProvider);
  final category = ref.watch(selectedCategoryProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  if (currentLocation == null || placesApiKey.isEmpty) {
    return const <Place>[];
  }
  return fetchNearbyPlaces(
    apiKey: placesApiKey,
    location: currentLocation,
    radiusMeters: radius,
    category: category,
    searchQuery: searchQuery,
  );
});

final favoritePlaceListProvider = Provider<List<Place>>((ref) {
  final favorites = ref.watch(favoritePlacesProvider);
  return ref
          .watch(nearbyPlacesProvider)
          .valueOrNull
          ?.where((place) => favorites.contains(place.name))
          .toList() ??
      const <Place>[];
});

final tripPlaceListProvider = Provider<List<Place>>((ref) {
  final tripPlaces = ref.watch(tripPlacesProvider);
  return ref
          .watch(nearbyPlacesProvider)
          .valueOrNull
          ?.where((place) => tripPlaces.contains(place.name))
          .toList() ??
      const <Place>[];
});

final filteredPlacesProvider = Provider<List<Place>>((ref) {
  final radius = ref.watch(selectedRadiusProvider);
  final category = ref.watch(selectedCategoryProvider);
  final filters = ref.watch(activeExploreFiltersProvider);
  final currentLocation = ref.watch(currentLocationProvider) ?? visitlyCenter;
  final places = ref.watch(nearbyPlacesProvider).valueOrNull ?? const <Place>[];
  final sortedPlaces =
      places
          .map(
            (place) => place.copyWith(
              distanceMeters: distanceBetween(currentLocation, place.position),
            ),
          )
          .where((place) => category == 'All' || place.category == category)
          .where((place) => filtersPlaces(place, filters))
          .toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return sortedPlaces.where((place) => place.distanceMeters <= radius).toList();
});

class VisitlyApp extends ConsumerWidget {
  const VisitlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Visitly',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(appRouterProvider),
      themeMode: ref.watch(themeModeProvider),
      theme: VisitlyTheme.light(),
      darkTheme: VisitlyTheme.dark(),
    );
  }
}

class VisitlyTheme {
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00A884),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0D1117)
          : const Color(0xFFF7FAF8),
      fontFamily: 'Roboto',
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark
            ? const Color(0xEE111820)
            : const Color(0xEEF9FFFB),
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class VisitlyShell extends ConsumerStatefulWidget {
  const VisitlyShell({super.key});

  @override
  ConsumerState<VisitlyShell> createState() => _VisitlyShellState();
}

class _VisitlyShellState extends ConsumerState<VisitlyShell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => updateCurrentLocation(ref));
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(activeTabProvider);
    final pages = [
      const MapHomeScreen(),
      const ExploreScreen(),
      const TripsScreen(),
      const FavoritesScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: 280.ms,
        child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) =>
            ref.read(activeTabProvider.notifier).state = value,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Saved',
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

class MapHomeScreen extends ConsumerWidget {
  const MapHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(filteredPlacesProvider);
    final radius = ref.watch(selectedRadiusProvider);
    final heatmap = ref.watch(heatmapEnabledProvider);
    final formatter = NumberFormat.decimalPattern();
    final foundCount = formatter.format(places.length);

    return Stack(
      children: [
        LiveGoogleMap(places: places, heatmap: heatmap),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              children: [
                GlassPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: const PlaceSearchBar(),
                ),
                const SizedBox(height: 12),
                CategoryRail(categories: categories),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 174,
          child: Column(
            children: [
              MapFab(
                icon: Icons.my_location,
                onTap: () => updateCurrentLocation(ref, context: context),
              ),
              const SizedBox(height: 10),
              MapFab(icon: Icons.explore, onTap: () {}),
              const SizedBox(height: 10),
              MapFab(icon: Icons.layers, onTap: () => cycleMapType(ref)),
              const SizedBox(height: 10),
              MapFab(
                icon: heatmap
                    ? Icons.local_fire_department
                    : Icons.local_fire_department_outlined,
                onTap: () =>
                    ref.read(heatmapEnabledProvider.notifier).state = !heatmap,
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(
            children: [
              GlassPanel(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.radar,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Slider(
                        value: radius.toDouble(),
                        min: 500,
                        max: 100000,
                        divisions: radiusOptions.length - 1,
                        onChanged: (value) =>
                            ref.read(selectedRadiusProvider.notifier).state =
                                nearestRadius(value),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatRadius(radius),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '$foundCount found',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (ref.watch(selectedPlaceProvider) case final place?)
                AnimatedWhenAllowed(
                  child: Dismissible(
                    key: ValueKey('preview-${place.name}'),
                    direction: DismissDirection.down,
                    onDismissed: (_) {
                      ref.read(selectedPlaceProvider.notifier).state = null;
                      ref.read(routeDestinationProvider.notifier).state = null;
                    },
                    child: PlacePreviewCard(place: place)
                        .animate()
                        .fadeIn(duration: 240.ms)
                        .slideY(begin: .12, end: 0, duration: 280.ms),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class LiveGoogleMap extends ConsumerStatefulWidget {
  const LiveGoogleMap({super.key, required this.places, required this.heatmap});

  final List<Place> places;
  final bool heatmap;

  @override
  ConsumerState<LiveGoogleMap> createState() => _LiveGoogleMapState();
}

class _LiveGoogleMapState extends ConsumerState<LiveGoogleMap> {
  GoogleMapController? _controller;
  Map<String, BitmapDescriptor> _markerIcons = const {};

  @override
  void initState() {
    super.initState();
    _refreshMarkerIcons();
  }

  @override
  void didUpdateWidget(covariant LiveGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_placeKey(oldWidget.places) != _placeKey(widget.places)) {
      _refreshMarkerIcons();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = ref.watch(selectedRadiusProvider);
    final selectedPlace = ref.watch(selectedPlaceProvider);
    final currentLocation = ref.watch(currentLocationProvider);
    final routeDestination = ref.watch(routeDestinationProvider);
    final mapType = ref.watch(mapTypeProvider);
    final mapCenter =
        selectedPlace?.position ?? currentLocation ?? visitlyCenter;
    final routeStart = currentLocation ?? visitlyCenter;
    ref.listen(currentLocationProvider, (previous, next) {
      if (next != null && previous != next && selectedPlace == null) {
        _controller?.animateCamera(CameraUpdate.newLatLngZoom(next, 13.6));
      }
    });
    ref.listen(routeDestinationProvider, (previous, next) {
      if (next != null) {
        _controller?.animateCamera(
          CameraUpdate.newLatLngBounds(
            boundsFor(routeStart, next.position),
            96,
          ),
        );
      }
    });
    final markers = {
      for (final entry in widget.places.indexed)
        Marker(
          markerId: MarkerId(entry.$2.name),
          position: entry.$2.position,
          infoWindow: InfoWindow(
            title: entry.$2.name,
            snippet: '${entry.$2.category} • ${entry.$2.rating} stars',
          ),
          icon: _markerIcons[entry.$2.name] ?? markerHueFor(entry.$2.category),
          onTap: () {
            ref.read(selectedPlaceProvider.notifier).state = entry.$2;
            ref.read(routeDestinationProvider.notifier).state = null;
            _controller?.animateCamera(
              CameraUpdate.newLatLngZoom(entry.$2.position, 14.6),
            );
          },
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: mapCenter, zoom: 13),
      onMapCreated: (controller) {
        _controller = controller;
        controller.animateCamera(CameraUpdate.newLatLngZoom(mapCenter, 13.6));
      },
      style: isDark ? darkMapStyle : lightMapStyle,
      onTap: (_) {
        ref.read(selectedPlaceProvider.notifier).state = null;
        ref.read(routeDestinationProvider.notifier).state = null;
      },
      onCameraMoveStarted: () {},
      mapType: mapType,
      markers: markers,
      polylines: {
        if (routeDestination != null)
          Polyline(
            polylineId: PolylineId('route-${routeDestination.name}'),
            points: [routeStart, routeDestination.position],
            color: Theme.of(context).colorScheme.primary,
            width: 6,
            patterns: [PatternItem.dash(28), PatternItem.gap(12)],
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
      },
      circles: {
        Circle(
          circleId: const CircleId('selected-radius'),
          center: mapCenter,
          radius: radius.toDouble(),
          strokeColor: const Color(0xFF00D6A3).withValues(alpha: .76),
          fillColor: const Color(0xFF00D6A3).withValues(alpha: .12),
          strokeWidth: 2,
        ),
        if (widget.heatmap)
          for (final place in widget.places.take(4))
            Circle(
              circleId: CircleId('heat-${place.name}'),
              center: place.position,
              radius: 650 + place.popularity * 12,
              strokeWidth: 0,
              fillColor: const Color(0xFFFFB84D).withValues(alpha: .16),
            ),
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      padding: const EdgeInsets.fromLTRB(0, 112, 0, 132),
    );
  }

  Future<void> _refreshMarkerIcons() async {
    final icons = <String, BitmapDescriptor>{};
    for (final entry in widget.places.indexed) {
      icons[entry.$2.name] = await buildPlaceMarkerIcon(
        place: entry.$2,
        rank: entry.$1 + 1,
      );
    }
    if (mounted) {
      setState(() => _markerIcons = icons);
    }
  }

  String _placeKey(List<Place> places) {
    return places.map((place) => place.name).join('|');
  }
}

class AnimatedWhenAllowed extends StatelessWidget {
  const AnimatedWhenAllowed({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations && child is Animate) {
      return (child as Animate).child;
    }
    return child;
  }
}

class PlaceSearchBar extends ConsumerStatefulWidget {
  const PlaceSearchBar({super.key});

  @override
  ConsumerState<PlaceSearchBar> createState() => _PlaceSearchBarState();
}

class _PlaceSearchBarState extends ConsumerState<PlaceSearchBar> {
  late final TextEditingController _controller;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    if (_controller.text != query) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    return Row(
      children: [
        const Icon(Icons.search, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Search attractions, food, cities',
              border: InputBorder.none,
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              ref.read(searchQueryProvider.notifier).state = value;
              ref.invalidate(nearbyPlacesProvider);
            },
          ),
        ),
        if (query.isNotEmpty)
          IconButton(
            onPressed: () {
              _controller.clear();
              ref.read(searchQueryProvider.notifier).state = '';
              ref.invalidate(nearbyPlacesProvider);
            },
            icon: const Icon(Icons.close),
          ),
        IconButton.filledTonal(
          onPressed: () => showFilterSheet(context, ref),
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          onPressed: _toggleVoiceSearch,
          icon: Icon(_listening ? Icons.mic : Icons.mic_none),
        ),
      ],
    );
  }

  Future<void> _toggleVoiceSearch() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
      }
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      if (mounted) {
        showVisitlyMessage(context, 'Voice search is not available');
      }
      return;
    }
    if (mounted) {
      setState(() => _listening = true);
    }
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      onResult: (result) {
        final words = result.recognizedWords;
        _controller.text = words;
        ref.read(searchQueryProvider.notifier).state = words;
        if (result.finalResult && mounted) {
          setState(() => _listening = false);
          ref.invalidate(nearbyPlacesProvider);
        }
      },
    );
  }
}

class PlacePreviewCard extends StatelessWidget {
  const PlacePreviewCard({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PlaceDetailSheet(place: place),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(28),
              ),
              child: CachedNetworkImage(
                imageUrl: place.imageUrl,
                width: 112,
                height: 116,
                fit: BoxFit.cover,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(place.icon, color: place.color, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          place.category,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          color: Color(0xFFFFB84D),
                          size: 18,
                        ),
                        Text(' ${place.rating}  ${place.reviews} reviews'),
                        const Spacer(),
                        Text(
                          formatRadius(place.distanceMeters),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaceDetailSheet extends ConsumerWidget {
  const PlaceDetailSheet({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritePlacesProvider);
    final tripPlaces = ref.watch(tripPlacesProvider);
    final isFavorite = favorites.contains(place.name);
    final isInTrip = tripPlaces.contains(place.name);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .86,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaceImageCarousel(place: place),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(place.description),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      StatPill(
                        icon: Icons.star,
                        label: '${place.rating} rating',
                      ),
                      StatPill(
                        icon: Icons.reviews,
                        label: '${place.reviews} reviews',
                      ),
                      StatPill(
                        icon: Icons.near_me,
                        label: formatRadius(place.distanceMeters),
                      ),
                      StatPill(
                        icon: Icons.local_fire_department,
                        label: '${place.popularity}% popular',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => navigateToPlace(context, ref, place),
                          icon: const Icon(Icons.navigation),
                          label: const Text('Navigate'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: () => toggleFavorite(context, ref, place),
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => sharePlace(context, place),
                        icon: const Icon(Icons.share),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Open now'),
                    subtitle: Text(place.hours),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Address'),
                    subtitle: Text(place.address),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_location_alt),
                    title: Text(isInTrip ? 'Added to trip' : 'Add to trip'),
                    subtitle: const Text(
                      'Estimate routes, travel time, and daily itinerary.',
                    ),
                    onTap: () => toggleTripPlace(context, ref, place),
                  ),
                  const SizedBox(height: 8),
                  DetailSection(
                    title: 'About',
                    child: Text(
                      '${place.description}\n\n${place.category} • ${place.address}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 18),
                  DetailSection(
                    title: 'User Reviews',
                    child: Column(
                      children: [
                        if (place.reviewSnippets.isEmpty)
                          const ReviewCard(
                            author: 'Visitors',
                            body:
                                'No written reviews are available yet. Ratings and popularity are shown above.',
                          )
                        else
                          for (final review in place.reviewSnippets.take(3))
                            ReviewCard(
                              author: review.author,
                              body: review.body,
                            ),
                      ],
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

class PlaceImageCarousel extends StatefulWidget {
  const PlaceImageCarousel({super.key, required this.place});
  final Place place;

  @override
  State<PlaceImageCarousel> createState() => _PlaceImageCarouselState();
}

class _PlaceImageCarouselState extends State<PlaceImageCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.place.allImageUrls;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SizedBox(
        height: 250,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) => CachedNetworkImage(
                imageUrl: images[index],
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final entry in images.indexed)
                    AnimatedContainer(
                      duration: 180.ms,
                      width: entry.$1 == _index ? 22 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: entry.$1 == _index ? .95 : .45,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_index + 1}/${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.author, required this.body});
  final String author;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  author,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }
}

class CategoryRail extends ConsumerWidget {
  const CategoryRail({super.key, required this.categories});
  final List<String> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCategoryProvider);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return FilterChip(
            selected: selected == category,
            onSelected: (_) =>
                ref.read(selectedCategoryProvider.notifier).state = category,
            label: Text(category),
            avatar: Icon(categoryIcon(category), size: 18),
          );
        },
      ),
    );
  }
}

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbySearch = ref.watch(nearbyPlacesProvider);
    final currentLocation = ref.watch(currentLocationProvider);
    final nearbyPlaces = ref.watch(filteredPlacesProvider);
    final activeFilters = ref.watch(activeExploreFiltersProvider);
    final mostVisited = [...nearbyPlaces]
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    final statusCard = nearbyPlacesStatusCard(
      nearbySearch: nearbySearch,
      currentLocation: currentLocation,
    );
    return AppPage(
      title: 'Explore',
      subtitle:
          'Trending nearby, hidden gems, family favorites, and weekend ideas.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SizedBox(height: 12),
          const GlassPanel(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: PlaceSearchBar(),
          ),
          if (statusCard != null) ...[const SizedBox(height: 18), statusCard],
          SectionTitle('Trending Nearby'),
          if (nearbyPlaces.isEmpty)
            const EmptyStateCard(
              icon: Icons.travel_explore,
              title: 'No nearby places yet',
              body: 'Set current location and make sure Places API is enabled.',
            )
          else
            PlaceGrid(places: nearbyPlaces.take(4).toList()),
          SectionTitle('Most Visited This Week'),
          if (mostVisited.isNotEmpty)
            PlaceGrid(places: mostVisited.take(4).toList()),
          SectionTitle('Smart Filters'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: smartFilters
                .map(
                  (label) => ActionChip(
                    label: Text(label),
                    avatar: const Icon(Icons.check_circle_outline),
                    backgroundColor: activeFilters.contains(label)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    onPressed: () => toggleExploreFilter(ref, label),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripPlaces = ref.watch(tripPlaceListProvider);
    return AppPage(
      title: 'Trips',
      subtitle: tripPlaces.isEmpty
          ? 'Add places from the detail sheet to build your trip.'
          : '${tripPlaces.length} stops added from nearby popular places.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (tripPlaces.isEmpty)
            const EmptyStateCard(
              icon: Icons.route,
              title: 'No trip places yet',
              body: 'Open any place detail and tap Add to trip.',
            )
          else
            TripPlanCard(
              title: 'My trip',
              places: tripPlaces,
              travelTime: estimateTripTime(tripPlaces),
              distance: formatRadius(totalTripDistance(tripPlaces)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref.read(activeTabProvider.notifier).state = 0,
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Build trip from map places'),
          ),
        ],
      ),
    );
  }
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedPlaces = ref.watch(favoritePlaceListProvider);
    return AppPage(
      title: 'Favorites',
      subtitle: savedPlaces.isEmpty
          ? 'Places you favorite will appear here.'
          : '${savedPlaces.length} saved places with ratings, hours, and offline details.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (savedPlaces.isEmpty)
            const EmptyStateCard(
              icon: Icons.favorite,
              title: 'No favorite places yet',
              body: 'Open any place detail and tap the heart button.',
            )
          else
            for (final place in savedPlaces) ...[
              SavedPlaceCard(place: place),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return AppPage(
      title: 'Profile',
      subtitle: 'Travel history, analytics, preferences, and theme settings.',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeatureCard(
            icon: Icons.insights,
            title: 'Your travel stats',
            body:
                '43 places visited • 186 km explored • Lahore is your top city',
          ),
          SwitchListTile.adaptive(
            value: mode == ThemeMode.dark,
            onChanged: (value) => ref.read(themeModeProvider.notifier).state =
                value ? ThemeMode.dark : ThemeMode.light,
            title: const Text('Dark theme'),
            secondary: const Icon(Icons.dark_mode),
          ),
          FeatureCard(
            icon: Icons.offline_pin,
            title: 'Offline cache',
            body: 'Favorites, recent places, and trip plans are ready offline.',
          ),
        ],
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(subtitle),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class PlaceGrid extends StatelessWidget {
  const PlaceGrid({super.key, required this.places});
  final List<Place> places;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: places.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .82,
      ),
      itemBuilder: (context, index) => PlaceTile(place: places[index]),
    );
  }
}

class PlaceTile extends StatelessWidget {
  const PlaceTile({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PlaceDetailSheet(place: place),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CachedNetworkImage(
              imageUrl: place.imageUrl,
              height: 118,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${place.category} • ${formatRadius(place.distanceMeters)}',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Color(0xFFFFB84D),
                        size: 16,
                      ),
                      Text(' ${place.rating}'),
                    ],
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

class TripPlanCard extends StatelessWidget {
  const TripPlanCard({
    super.key,
    required this.title,
    required this.places,
    required this.travelTime,
    required this.distance,
  });

  final String title;
  final List<Place> places;
  final String travelTime;
  final String distance;

  @override
  Widget build(BuildContext context) {
    final topPlace = places.reduce(
      (a, b) => a.popularity > b.popularity ? a : b,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedNetworkImage(
            imageUrl: topPlace.imageUrl,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Icon(
                      Icons.route,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${places.length} stops • $travelTime • $distance'),
                const SizedBox(height: 14),
                for (final entry in places.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: entry.$2.color.withValues(alpha: .16),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${entry.$1 + 1}',
                              style: TextStyle(
                                color: entry.$2.color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.$2.name,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${entry.$2.category} • ${entry.$2.hours}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SavedPlaceCard extends StatelessWidget {
  const SavedPlaceCard({super.key, required this.place});
  final Place place;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PlaceDetailSheet(place: place),
        ),
        child: Row(
          children: [
            CachedNetworkImage(
              imageUrl: place.imageUrl,
              width: 96,
              height: 112,
              fit: BoxFit.cover,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(place.icon, color: place.color, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place.category,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const Icon(
                          Icons.favorite,
                          color: Color(0xFFE75A3C),
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatRadius(place.distanceMeters)} • ${place.hours}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          color: Color(0xFFFFB84D),
                          size: 16,
                        ),
                        Text(' ${place.rating}'),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.local_fire_department,
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        ),
                        Text(' ${place.popularity}%'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        minVerticalPadding: 18,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(body),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 32),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}

Widget? nearbyPlacesStatusCard({
  required AsyncValue<List<Place>> nearbySearch,
  required LatLng? currentLocation,
}) {
  if (currentLocation == null) {
    return const EmptyStateCard(
      icon: Icons.my_location,
      title: 'Waiting for your location',
      body:
          'Allow location access or set a simulator location to load nearby places.',
    );
  }
  if (placesApiKey.isEmpty) {
    return const EmptyStateCard(
      icon: Icons.key,
      title: 'Places API key missing',
      body:
          'Run with --dart-define=MAPS_API_KEY=YOUR_KEY to load dynamic nearby places.',
    );
  }
  return nearbySearch.when(
    data: (places) {
      if (places.isEmpty) {
        return const EmptyStateCard(
          icon: Icons.search_off,
          title: 'No places found',
          body: 'Try a larger radius or a different category.',
        );
      }
      return null;
    },
    error: (_, _) => const EmptyStateCard(
      icon: Icons.error_outline,
      title: 'Could not load nearby places',
      body: 'Check that Places API is enabled for this key.',
    ),
    loading: () => const EmptyStateCard(
      icon: Icons.travel_explore,
      title: 'Loading nearby places',
      body: 'Searching around your current location.',
    ),
  );
}

void showFilterSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final selectedCategory = ref.watch(selectedCategoryProvider);
        final radius = ref.watch(selectedRadiusProvider);
        final activeFilters = ref.watch(activeExploreFiltersProvider);
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            shrinkWrap: true,
            children: [
              Text('Filters', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              Text('Category', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    FilterChip(
                      selected: selectedCategory == category,
                      label: Text(category),
                      avatar: Icon(categoryIcon(category), size: 18),
                      onSelected: (_) {
                        ref.read(selectedCategoryProvider.notifier).state =
                            category;
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Radius', style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: radius.toDouble(),
                min: 500,
                max: 100000,
                divisions: radiusOptions.length - 1,
                label: formatRadius(radius),
                onChanged: (value) =>
                    ref.read(selectedRadiusProvider.notifier).state =
                        nearestRadius(value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(formatRadius(radius)),
              ),
              const SizedBox(height: 12),
              Text(
                'Smart Filters',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in smartFilters)
                    FilterChip(
                      selected: activeFilters.contains(filter),
                      label: Text(filter),
                      onSelected: (_) => toggleExploreFilter(ref, filter),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: isDark ? .34 : .68,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .16),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class MapFab extends StatelessWidget {
  const MapFab({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        tooltip: icon.toString(),
      ),
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
    );
  }
}

class Place {
  const Place({
    required this.name,
    required this.category,
    required this.description,
    required this.imageUrl,
    required this.rating,
    required this.reviews,
    required this.distanceMeters,
    required this.popularity,
    required this.position,
    required this.icon,
    required this.color,
    required this.hours,
    required this.address,
    this.imageUrls = const [],
    this.reviewSnippets = const [],
  });

  final String name;
  final String category;
  final String description;
  final String imageUrl;
  final double rating;
  final int reviews;
  final int distanceMeters;
  final int popularity;
  final LatLng position;
  final IconData icon;
  final Color color;
  final String hours;
  final String address;
  final List<String> imageUrls;
  final List<ReviewSnippet> reviewSnippets;

  factory Place.fromGooglePlace(
    Map<String, dynamic> json,
    String apiKey,
    LatLng currentLocation,
  ) {
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final location = json['location'] as Map<String, dynamic>? ?? const {};
    final latitude = (location['latitude'] as num?)?.toDouble() ?? 0;
    final longitude = (location['longitude'] as num?)?.toDouble() ?? 0;
    final position = LatLng(latitude, longitude);
    final types = (json['types'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final primaryType = json['primaryType'] as String?;
    final category = categoryForGooglePlace(types, primaryType);
    final photos = json['photos'] as List<dynamic>? ?? const [];
    final photoMaps = photos.whereType<Map<String, dynamic>>().toList();
    final imageUrls = photoMaps
        .map((photo) => photo['name'] as String?)
        .whereType<String>()
        .map(
          (photoName) =>
              'https://places.googleapis.com/v1/$photoName/media?maxHeightPx=700&maxWidthPx=1000&key=$apiKey',
        )
        .toList();
    final name = displayName?['text'] as String? ?? 'Nearby place';
    final reviews = (json['userRatingCount'] as num?)?.toInt() ?? 0;
    final rating = (json['rating'] as num?)?.toDouble() ?? 0;
    return Place(
      name: name,
      category: category,
      description: descriptionForGooglePlace(category, reviews),
      imageUrl: imageUrls.isEmpty ? placeholderImageFor(name) : imageUrls.first,
      rating: rating,
      reviews: reviews,
      distanceMeters: distanceBetween(currentLocation, position),
      popularity: popularityFor(rating, reviews),
      position: position,
      icon: categoryIcon(category),
      color: colorForCategory(category),
      hours: hoursForGooglePlace(json),
      address: json['formattedAddress'] as String? ?? 'Address unavailable',
      imageUrls: imageUrls,
      reviewSnippets: reviewSnippetsForGooglePlace(json),
    );
  }

  List<String> get allImageUrls {
    if (imageUrls.isEmpty) {
      return [imageUrl];
    }
    return imageUrls;
  }

  Place copyWith({int? distanceMeters}) {
    return Place(
      name: name,
      category: category,
      description: description,
      imageUrl: imageUrl,
      rating: rating,
      reviews: reviews,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      popularity: popularity,
      position: position,
      icon: icon,
      color: color,
      hours: hours,
      address: address,
      imageUrls: imageUrls,
      reviewSnippets: reviewSnippets,
    );
  }
}

class ReviewSnippet {
  const ReviewSnippet({required this.author, required this.body});
  final String author;
  final String body;
}

const categories = [
  'All',
  'Attractions',
  'Restaurants',
  'Cafes',
  'Shopping',
  'Parks',
  'Museums',
  'Landmarks',
  'Mosques',
  'Entertainment',
  'Markets',
  'Photography',
];

const smartFilters = [
  'Open Now',
  'Family Friendly',
  'Free Entry',
  'Wheelchair Access',
  'Indoor',
  'Outdoor',
];

const radiusOptions = [500, 1000, 2000, 5000, 10000, 25000, 50000, 100000];

String formatRadius(int meters) =>
    meters < 1000 ? '$meters m' : '${meters ~/ 1000} km';

int nearestRadius(double value) {
  return radiusOptions.reduce(
    (a, b) => (value - a).abs() < (value - b).abs() ? a : b,
  );
}

void toggleExploreFilter(WidgetRef ref, String filter) {
  final current = ref.read(activeExploreFiltersProvider);
  final next = {...current};
  if (!next.add(filter)) {
    next.remove(filter);
  }
  ref.read(activeExploreFiltersProvider.notifier).state = next;
}

bool filtersPlaces(Place place, Set<String> filters) {
  if (filters.isEmpty) {
    return true;
  }
  for (final filter in filters) {
    final matches = switch (filter) {
      'Open Now' => place.hours == 'Open now',
      'Family Friendly' => {
        'Parks',
        'Museums',
        'Attractions',
        'Entertainment',
      }.contains(place.category),
      'Free Entry' => {
        'Parks',
        'Landmarks',
        'Markets',
      }.contains(place.category),
      'Wheelchair Access' => {
        'Museums',
        'Shopping',
        'Restaurants',
        'Cafes',
        'Entertainment',
      }.contains(place.category),
      'Indoor' => {
        'Museums',
        'Shopping',
        'Restaurants',
        'Cafes',
        'Entertainment',
      }.contains(place.category),
      'Outdoor' => {'Parks', 'Landmarks', 'Markets'}.contains(place.category),
      _ => true,
    };
    if (!matches) {
      return false;
    }
  }
  return true;
}

String placeholderImageFor(String name) {
  return 'https://placehold.co/900x600/10231f/d7eee5?text=${Uri.encodeComponent(name)}';
}

String descriptionForGooglePlace(String category, int reviews) {
  final reviewText = reviews == 0
      ? 'nearby visitor interest'
      : NumberFormat.compact().format(reviews);
  return switch (category) {
    'Restaurants' =>
      'A nearby restaurant with local dining options and $reviewText reviews.',
    'Cafes' => 'A nearby cafe for coffee, quick bites, and relaxed stops.',
    'Shopping' =>
      'A nearby shopping spot with stores, services, and visitor activity.',
    'Parks' =>
      'A nearby outdoor place for walks, fresh air, and casual visits.',
    'Museums' =>
      'A nearby museum or cultural stop with exhibits and visitor interest.',
    'Markets' =>
      'A nearby market with local vendors, food, and everyday essentials.',
    'Entertainment' =>
      'A nearby entertainment spot for events, shows, or activities.',
    'Landmarks' =>
      'A nearby landmark with local history and sightseeing appeal.',
    'Mosques' => 'A nearby mosque with visitor and prayer-hour relevance.',
    _ => 'A nearby place found from your current location.',
  };
}

String hoursForGooglePlace(Map<String, dynamic> json) {
  final hours = json['regularOpeningHours'] as Map<String, dynamic>?;
  final openNow = hours?['openNow'] as bool?;
  if (openNow != null) {
    return openNow ? 'Open now' : 'Closed now';
  }
  return 'Hours unavailable';
}

List<ReviewSnippet> reviewSnippetsForGooglePlace(Map<String, dynamic> json) {
  final reviews = json['reviews'] as List<dynamic>? ?? const [];
  return reviews
      .whereType<Map<String, dynamic>>()
      .map((review) {
        final author = review['authorAttribution'] as Map<String, dynamic>?;
        final text = review['text'] as Map<String, dynamic>?;
        return ReviewSnippet(
          author: author?['displayName'] as String? ?? 'Google user',
          body: text?['text'] as String? ?? '',
        );
      })
      .where((review) => review.body.trim().isNotEmpty)
      .toList();
}

int popularityFor(double rating, int reviews) {
  if (rating <= 0 && reviews == 0) {
    return 60;
  }
  final reviewScore = (reviews / 250).clamp(0, 40).round();
  return ((rating / 5) * 60).round() + reviewScore;
}

Color colorForCategory(String category) {
  return switch (category) {
    'Restaurants' => const Color(0xFFE75A3C),
    'Cafes' => const Color(0xFF14B8A6),
    'Shopping' => const Color(0xFF8B5CF6),
    'Parks' => const Color(0xFF1EAD66),
    'Museums' => const Color(0xFF6D8A96),
    'Landmarks' => const Color(0xFF00A884),
    'Mosques' => const Color(0xFF14B8A6),
    'Entertainment' => const Color(0xFFFFB84D),
    'Markets' => const Color(0xFFE75A3C),
    'Photography' => const Color(0xFF2B7FFF),
    _ => const Color(0xFF00A884),
  };
}

int distanceBetween(LatLng from, LatLng to) {
  return Geolocator.distanceBetween(
    from.latitude,
    from.longitude,
    to.latitude,
    to.longitude,
  ).round();
}

int totalTripDistance(List<Place> places) {
  return places.fold<int>(0, (total, place) => total + place.distanceMeters);
}

String estimateTripTime(List<Place> places) {
  final minutes =
      (places.length * 35) + (totalTripDistance(places) / 450).round();
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) {
    return '${remainingMinutes}m';
  }
  return remainingMinutes == 0 ? '${hours}h' : '${hours}h ${remainingMinutes}m';
}

LatLngBounds boundsFor(LatLng a, LatLng b) {
  return LatLngBounds(
    southwest: LatLng(
      a.latitude < b.latitude ? a.latitude : b.latitude,
      a.longitude < b.longitude ? a.longitude : b.longitude,
    ),
    northeast: LatLng(
      a.latitude > b.latitude ? a.latitude : b.latitude,
      a.longitude > b.longitude ? a.longitude : b.longitude,
    ),
  );
}

IconData categoryIcon(String category) {
  return switch (category) {
    'Attractions' => Icons.attractions,
    'Restaurants' => Icons.restaurant,
    'Cafes' => Icons.local_cafe,
    'Shopping' => Icons.shopping_bag,
    'Parks' => Icons.park,
    'Museums' => Icons.museum,
    'Landmarks' => Icons.account_balance,
    'Mosques' => Icons.mosque,
    'Entertainment' => Icons.theaters,
    'Markets' => Icons.storefront,
    'Photography' => Icons.photo_camera,
    _ => Icons.travel_explore,
  };
}

Future<List<Place>> fetchNearbyPlaces({
  required String apiKey,
  required LatLng location,
  required int radiusMeters,
  required String category,
  required String searchQuery,
}) async {
  final includedType = googlePlaceTypeFor(category);
  final trimmedQuery = searchQuery.trim();
  final effectiveRadius = radiusMeters.clamp(1, 50000);
  final circle = {
    'center': {'latitude': location.latitude, 'longitude': location.longitude},
    'radius': effectiveRadius,
  };
  final isTextSearch = trimmedQuery.isNotEmpty;
  final body = <String, Object?>{
    'maxResultCount': 20,
    if (isTextSearch) ...{
      'textQuery':
          '$trimmedQuery near ${location.latitude}, ${location.longitude}',
      'locationBias': {'circle': circle},
    } else ...{
      'rankPreference': 'DISTANCE',
      'locationRestriction': {'circle': circle},
      if (includedType != null) 'includedTypes': [includedType],
    },
  };
  final endpoint = isTextSearch
      ? 'https://places.googleapis.com/v1/places:searchText'
      : 'https://places.googleapis.com/v1/places:searchNearby';
  final response = await http.post(
    Uri.parse(endpoint),
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask':
          'places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.types,places.primaryType,places.primaryTypeDisplayName,places.regularOpeningHours,places.photos,places.reviews',
    },
    body: jsonEncode(body),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Nearby search failed: ${response.statusCode}');
  }

  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  final places =
      (payload['places'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (placeJson) => Place.fromGooglePlace(placeJson, apiKey, location),
          )
          .toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return places;
}

String? googlePlaceTypeFor(String category) {
  return switch (category) {
    'Attractions' => 'tourist_attraction',
    'Restaurants' => 'restaurant',
    'Cafes' => 'cafe',
    'Shopping' => 'shopping_mall',
    'Parks' => 'park',
    'Museums' => 'museum',
    'Landmarks' => 'historical_landmark',
    'Mosques' => 'mosque',
    'Entertainment' => 'amusement_center',
    'Markets' => 'market',
    'Photography' => 'tourist_attraction',
    _ => null,
  };
}

String categoryForGooglePlace(List<String> types, String? primaryType) {
  final allTypes = {?primaryType, ...types};
  if (allTypes.contains('restaurant')) return 'Restaurants';
  if (allTypes.contains('cafe')) return 'Cafes';
  if (allTypes.contains('shopping_mall') || allTypes.contains('store')) {
    return 'Shopping';
  }
  if (allTypes.contains('park')) return 'Parks';
  if (allTypes.contains('museum')) return 'Museums';
  if (allTypes.contains('mosque')) return 'Mosques';
  if (allTypes.contains('market') || allTypes.contains('supermarket')) {
    return 'Markets';
  }
  if (allTypes.contains('historical_landmark') ||
      allTypes.contains('monument')) {
    return 'Landmarks';
  }
  if (allTypes.contains('amusement_center') ||
      allTypes.contains('stadium') ||
      allTypes.contains('performing_arts_theater')) {
    return 'Entertainment';
  }
  return 'Attractions';
}

void cycleMapType(WidgetRef ref) {
  final current = ref.read(mapTypeProvider);
  ref.read(mapTypeProvider.notifier).state = switch (current) {
    MapType.normal => MapType.hybrid,
    MapType.hybrid => MapType.terrain,
    MapType.terrain => MapType.satellite,
    MapType.satellite => MapType.normal,
    _ => MapType.normal,
  };
}

Future<void> updateCurrentLocation(
  WidgetRef ref, {
  BuildContext? context,
}) async {
  final messenger = context == null ? null : ScaffoldMessenger.of(context);
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Turn on location services to find nearby places'),
        ),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Location permission is needed for nearby places'),
        ),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    ref.read(currentLocationProvider.notifier).state = LatLng(
      position.latitude,
      position.longitude,
    );
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Updated nearby places')));
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not get current location')),
    );
  }
}

void navigateToPlace(BuildContext context, WidgetRef ref, Place place) {
  ref.read(selectedPlaceProvider.notifier).state = place;
  ref.read(routeDestinationProvider.notifier).state = place;
  ref.read(activeTabProvider.notifier).state = 0;
  Navigator.of(context).maybePop();
  showVisitlyMessage(context, 'Route to ${place.name} is on the map');
}

void toggleFavorite(BuildContext context, WidgetRef ref, Place place) {
  final current = ref.read(favoritePlacesProvider);
  final next = {...current};
  final removed = !next.add(place.name);
  if (removed) {
    next.remove(place.name);
  }
  ref.read(favoritePlacesProvider.notifier).state = next;
  showVisitlyMessage(
    context,
    removed ? 'Removed from saved places' : 'Saved ${place.name}',
  );
}

void toggleTripPlace(BuildContext context, WidgetRef ref, Place place) {
  final current = ref.read(tripPlacesProvider);
  final next = {...current};
  final removed = !next.add(place.name);
  if (removed) {
    next.remove(place.name);
  }
  ref.read(tripPlacesProvider.notifier).state = next;
  showVisitlyMessage(
    context,
    removed ? 'Removed from trip' : 'Added ${place.name} to trip',
  );
}

Future<void> sharePlace(BuildContext context, Place place) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(
    ClipboardData(
      text:
          '${place.name}\n${place.description}\nRating: ${place.rating} • Distance: ${formatRadius(place.distanceMeters)}',
    ),
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Place details copied to share')),
    );
}

void showVisitlyMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

BitmapDescriptor markerHueFor(String category) {
  final hue = switch (category) {
    'Restaurants' => BitmapDescriptor.hueOrange,
    'Shopping' => BitmapDescriptor.hueViolet,
    'Parks' => BitmapDescriptor.hueGreen,
    'Museums' => BitmapDescriptor.hueAzure,
    'Landmarks' => BitmapDescriptor.hueCyan,
    'Mosques' => BitmapDescriptor.hueCyan,
    'Entertainment' => BitmapDescriptor.hueYellow,
    'Photography' => BitmapDescriptor.hueBlue,
    _ => BitmapDescriptor.hueRose,
  };
  return BitmapDescriptor.defaultMarkerWithHue(hue);
}

Future<BitmapDescriptor> buildPlaceMarkerIcon({
  required Place place,
  required int rank,
}) async {
  const size = 112.0;
  const center = Offset(size / 2, 42);
  final color = markerColorForRank(rank);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: .24)
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
  final shadowPath = pinPath(center.translate(0, 4));
  canvas.drawPath(shadowPath, shadowPaint);

  final pinPaint = Paint()..color = color;
  final borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6;
  final pin = pinPath(center);
  canvas.drawPath(pin, pinPaint);
  canvas.drawPath(pin, borderPaint);

  canvas.drawCircle(center.translate(0, -2), 20, Paint()..color = Colors.white);
  final labelPainter = TextPainter(
    text: TextSpan(
      text: rank > 99 ? '99+' : '$rank',
      style: TextStyle(
        color: color,
        fontSize: rank > 99 ? 17 : 22,
        fontWeight: FontWeight.w900,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  labelPainter.paint(
    canvas,
    center.translate(-labelPainter.width / 2, -2 - labelPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}

Path pinPath(Offset center) {
  final path = Path()
    ..addOval(Rect.fromCircle(center: center, radius: 31))
    ..moveTo(center.dx - 19, center.dy + 22)
    ..quadraticBezierTo(
      center.dx,
      center.dy + 64,
      center.dx + 19,
      center.dy + 22,
    )
    ..close();
  return path;
}

Color markerColorForRank(int rank) {
  const palette = [
    Color(0xFFE91E63),
    Color(0xFF7C3AED),
    Color(0xFFFF7A1A),
    Color(0xFF00A884),
    Color(0xFF2B7FFF),
    Color(0xFFE75A3C),
    Color(0xFF14B8A6),
    Color(0xFFFFB84D),
    Color(0xFF8B5CF6),
    Color(0xFF1EAD66),
  ];
  return palette[(rank - 1) % palette.length];
}

const visitlyCenter = LatLng(31.5657, 74.3142);
const sanFranciscoCenter = LatLng(37.7749, -122.4194);

const darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#15211f"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#d7eee5"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1110"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#295047"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#20352f"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#123b30"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#263d38"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#0d1715"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3a5c52"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#20322e"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b2f42"}]}
]
''';

const lightMapStyle = '''
[
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#b7e7dc"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#e3f4ec"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#ccebd6"}]}
]
''';

final samplePlaces = [
  const Place(
    name: 'Royal Fort Gardens',
    category: 'Landmarks',
    description:
        'A high-traffic heritage destination with sunset viewpoints, guided walks, and family-friendly courtyards.',
    imageUrl:
        'https://images.unsplash.com/photo-1609948543911-7f01ff385be5?auto=format&fit=crop&w=900&q=80',
    rating: 4.8,
    reviews: 12840,
    distanceMeters: 850,
    popularity: 98,
    position: LatLng(31.5880, 74.3150),
    icon: Icons.account_balance,
    color: Color(0xFF00A884),
    hours: '9:00 AM - 10:30 PM',
    address: 'Fort Road, Walled City, Lahore',
  ),
  const Place(
    name: 'Old City Food Street',
    category: 'Restaurants',
    description:
        'A lively corridor of local favorites, rooftop dining, and trending street food stalls.',
    imageUrl:
        'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=900&q=80',
    rating: 4.7,
    reviews: 18410,
    distanceMeters: 1400,
    popularity: 96,
    position: LatLng(31.5848, 74.3137),
    icon: Icons.restaurant,
    color: Color(0xFFE75A3C),
    hours: '12:00 PM - 1:00 AM',
    address: 'Food Street, Fort Road, Old City Lahore',
  ),
  const Place(
    name: 'Emerald Lake Viewpoint',
    category: 'Photography',
    description:
        'A calm viewpoint popular for landscape photos, morning walks, and weekend recommendations.',
    imageUrl:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=80',
    rating: 4.6,
    reviews: 6920,
    distanceMeters: 4200,
    popularity: 88,
    position: LatLng(31.5488, 74.3318),
    icon: Icons.photo_camera,
    color: Color(0xFF2B7FFF),
    hours: 'Open 24 hours',
    address: 'Mall Road Viewpoint, Lahore',
  ),
  const Place(
    name: 'Pearl Avenue Mall',
    category: 'Shopping',
    description:
        'Premium shopping, cinemas, cafes, indoor entertainment, and accessible family facilities.',
    imageUrl:
        'https://images.unsplash.com/photo-1519567241046-7f570eee3ce6?auto=format&fit=crop&w=900&q=80',
    rating: 4.5,
    reviews: 9320,
    distanceMeters: 6800,
    popularity: 83,
    position: LatLng(31.4697, 74.2728),
    icon: Icons.shopping_bag,
    color: Color(0xFF8B5CF6),
    hours: '10:00 AM - 11:00 PM',
    address: 'Pearl Avenue, Gulberg, Lahore',
  ),
  const Place(
    name: 'Botanical Family Park',
    category: 'Parks',
    description:
        'Outdoor family favorite with trails, picnic lawns, lakeside seating, and weekend events.',
    imageUrl:
        'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=900&q=80',
    rating: 4.4,
    reviews: 5480,
    distanceMeters: 9800,
    popularity: 79,
    position: LatLng(31.4979, 74.3188),
    icon: Icons.park,
    color: Color(0xFF1EAD66),
    hours: '6:00 AM - 9:00 PM',
    address: 'Canal Bank Road, Lahore',
  ),
  const Place(
    name: 'Skyline Theme Park',
    category: 'Entertainment',
    description:
        'Rides, arcades, live shows, and high-energy nightlife with strong family and tourist appeal.',
    imageUrl:
        'https://images.unsplash.com/photo-1513889961551-628c1e5e2ee9?auto=format&fit=crop&w=900&q=80',
    rating: 4.3,
    reviews: 11870,
    distanceMeters: 17000,
    popularity: 91,
    position: LatLng(31.5190, 74.3556),
    icon: Icons.attractions,
    color: Color(0xFFFFB84D),
    hours: '11:00 AM - 12:00 AM',
    address: 'Main Boulevard, Lahore',
  ),
  const Place(
    name: 'Sapphire Grand Mosque',
    category: 'Mosques',
    description:
        'A serene architectural landmark with guided visitor hours and a spacious courtyard.',
    imageUrl:
        'https://images.unsplash.com/photo-1589952283406-b53a7d1347e8?auto=format&fit=crop&w=900&q=80',
    rating: 4.9,
    reviews: 7400,
    distanceMeters: 26000,
    popularity: 86,
    position: LatLng(31.5887, 74.3094),
    icon: Icons.mosque,
    color: Color(0xFF14B8A6),
    hours: '5:00 AM - 10:00 PM',
    address: 'Circular Road, Walled City, Lahore',
  ),
  const Place(
    name: 'City History Museum',
    category: 'Museums',
    description:
        'Curated exhibits, cultural artifacts, audio tours, and indoor discovery for all ages.',
    imageUrl:
        'https://images.unsplash.com/photo-1566054757965-8c4085344c96?auto=format&fit=crop&w=900&q=80',
    rating: 4.5,
    reviews: 3860,
    distanceMeters: 41000,
    popularity: 74,
    position: LatLng(31.5688, 74.3085),
    icon: Icons.museum,
    color: Color(0xFF6D8A96),
    hours: '10:00 AM - 6:00 PM',
    address: 'The Mall, Lahore',
  ),
];

final sanFranciscoPlaces = [
  const Place(
    name: 'Ferry Building Marketplace',
    category: 'Markets',
    description:
        'A waterfront food hall with local vendors, coffee, bay views, and a busy farmers market.',
    imageUrl:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=80',
    rating: 4.7,
    reviews: 22410,
    distanceMeters: 0,
    popularity: 97,
    position: LatLng(37.7955, -122.3937),
    icon: Icons.storefront,
    color: Color(0xFFE75A3C),
    hours: '7:00 AM - 8:00 PM',
    address: '1 Ferry Building, San Francisco, CA',
  ),
  const Place(
    name: 'Exploratorium',
    category: 'Museums',
    description:
        'Hands-on science exhibits, waterfront installations, and family-friendly discovery spaces.',
    imageUrl:
        'https://images.unsplash.com/photo-1566054757965-8c4085344c96?auto=format&fit=crop&w=900&q=80',
    rating: 4.8,
    reviews: 16480,
    distanceMeters: 0,
    popularity: 94,
    position: LatLng(37.8014, -122.3988),
    icon: Icons.museum,
    color: Color(0xFF8B5CF6),
    hours: '10:00 AM - 5:00 PM',
    address: 'Pier 15, The Embarcadero, San Francisco, CA',
  ),
  const Place(
    name: 'Union Square',
    category: 'Shopping',
    description:
        'Central shopping district with hotels, theaters, public art, and walkable dining nearby.',
    imageUrl:
        'https://images.unsplash.com/photo-1519567241046-7f570eee3ce6?auto=format&fit=crop&w=900&q=80',
    rating: 4.5,
    reviews: 19830,
    distanceMeters: 0,
    popularity: 92,
    position: LatLng(37.7880, -122.4075),
    icon: Icons.shopping_bag,
    color: Color(0xFF2B7FFF),
    hours: 'Open 24 hours',
    address: '333 Post St, San Francisco, CA',
  ),
  const Place(
    name: 'San Francisco Museum of Modern Art',
    category: 'Museums',
    description:
        'Modern and contemporary art galleries, rotating exhibitions, and architecture-focused visits.',
    imageUrl:
        'https://images.unsplash.com/photo-1566127444979-b3d2b654e3d7?auto=format&fit=crop&w=900&q=80',
    rating: 4.6,
    reviews: 12690,
    distanceMeters: 0,
    popularity: 89,
    position: LatLng(37.7857, -122.4011),
    icon: Icons.museum,
    color: Color(0xFF6D8A96),
    hours: '10:00 AM - 5:00 PM',
    address: '151 3rd St, San Francisco, CA',
  ),
  const Place(
    name: 'Oracle Park',
    category: 'Entertainment',
    description:
        'Bayfront ballpark with skyline views, events, tours, and game-day food favorites.',
    imageUrl:
        'https://images.unsplash.com/photo-1540747913346-19e32dc3e97e?auto=format&fit=crop&w=900&q=80',
    rating: 4.7,
    reviews: 28750,
    distanceMeters: 0,
    popularity: 93,
    position: LatLng(37.7786, -122.3893),
    icon: Icons.stadium,
    color: Color(0xFFFFB84D),
    hours: 'Event hours vary',
    address: '24 Willie Mays Plaza, San Francisco, CA',
  ),
  const Place(
    name: 'Salesforce Park',
    category: 'Parks',
    description:
        'Elevated urban park with gardens, walking paths, public art, and downtown views.',
    imageUrl:
        'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=900&q=80',
    rating: 4.6,
    reviews: 8350,
    distanceMeters: 0,
    popularity: 87,
    position: LatLng(37.7897, -122.3961),
    icon: Icons.park,
    color: Color(0xFF1EAD66),
    hours: '6:00 AM - 9:00 PM',
    address: '425 Mission St, San Francisco, CA',
  ),
  const Place(
    name: 'Cable Car Museum',
    category: 'Museums',
    description:
        'Historic cable car exhibits, working machinery, vintage cars, and classic city transport stories.',
    imageUrl:
        'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=900&q=80',
    rating: 4.7,
    reviews: 9120,
    distanceMeters: 0,
    popularity: 85,
    position: LatLng(37.7948, -122.4118),
    icon: Icons.museum,
    color: Color(0xFF14B8A6),
    hours: '10:00 AM - 4:00 PM',
    address: '1201 Mason St, San Francisco, CA',
  ),
  const Place(
    name: 'Chase Center',
    category: 'Entertainment',
    description:
        'Arena district for concerts, basketball, waterfront dining, and large events.',
    imageUrl:
        'https://images.unsplash.com/photo-1513889961551-628c1e5e2ee9?auto=format&fit=crop&w=900&q=80',
    rating: 4.6,
    reviews: 14760,
    distanceMeters: 0,
    popularity: 90,
    position: LatLng(37.7680, -122.3877),
    icon: Icons.sports_basketball,
    color: Color(0xFFE75A3C),
    hours: 'Event hours vary',
    address: '1 Warriors Way, San Francisco, CA',
  ),
];
