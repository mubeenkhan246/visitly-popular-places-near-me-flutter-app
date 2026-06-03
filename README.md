# Visitly - Most Visited Places

Visitly is a Flutter travel discovery app that finds popular nearby places from the user's current location. It includes an interactive Google Map, dynamic nearby search, place detail sheets, image sliders, reviews, favorites, trips, route preview, filters, and voice search.

## Features

- Current-location based nearby places
- Google Maps integration with custom ranked pin markers
- Google Places nearby and text search
- Search by name, category, address, or voice
- Category chips and smart filters
- Radius slider up to 100 km
- Place detail bottom sheet with image carousel
- Address, opening status, about section, and user reviews
- Favorite places page from user-selected favorites
- Trip page from user-added trip stops
- Route preview from current location to selected place
- Dark and light theme support

## Tech Stack

- Flutter
- Riverpod
- Google Maps Flutter
- Google Places Web Service
- Geolocator
- Speech to Text
- Cached Network Image

## Requirements

- Flutter SDK
- Android Studio or Xcode
- Google Maps API key
- Google Maps SDK enabled for Android/iOS
- Places API enabled for dynamic nearby places

## Setup

Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/most_visited_places.git
cd most_visited_places
```

Install dependencies:

```bash
flutter pub get
```

Run the app with your Google API key:

```bash
flutter run --dart-define=MAPS_API_KEY=YOUR_GOOGLE_MAPS_KEY
```

The native Google Maps SDK also reads `MAPS_API_KEY` from the platform configuration. Make sure your local Android/iOS setup provides the same key for map rendering.

## iOS Notes

The app uses:

- Location permission
- Microphone permission
- Speech recognition permission

If testing in the iOS Simulator, set a simulated location:

```text
Simulator > Features > Location
```

## Android Notes

The app uses:

- Fine/coarse location permission
- Microphone permission

Make sure your Google Maps key is available to Android and that the Maps SDK is enabled in Google Cloud.

## Testing

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

## Project Structure

```text
lib/main.dart              Main app, providers, screens, models, Google Places integration
android/                   Android platform project
ios/                       iOS platform project
test/widget_test.dart      Widget tests
```

## API Key Security

Do not commit real API keys to the repository. Use `--dart-define`, local platform config, CI secrets, or environment-specific files ignored by Git.

Restrict your Google API key in Google Cloud by:

- App bundle/package identifiers
- API usage
- Platform
- Referrer or SHA certificate where applicable

## License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
