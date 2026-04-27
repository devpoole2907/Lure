# Lure — Claude Code Integration Guide

> **Context**: Lure is a native iOS Seerr client for media discovery and requests.
> These files form a complete app skeleton. Your job is to create the Xcode project,
> add these files, fix any compilation issues, and ensure everything runs.

---

## Project Setup

| Key | Value |
|-----|-------|
| App Name | `Lure` |
| Bundle ID | `com.poole.james.Lure` |
| Min Deployment | iOS 26.0 |
| Swift Version | 6.0 |
| URL Scheme | `lure` (for deep links) |

---

## Hard Constraints

1. **iOS 26 only.** No `#available` checks.
2. **`@Observable` only.** No ObservableObject, @Published, @StateObject, @ObservedObject.
3. **No Combine.** Zero `import Combine`.
4. **No DispatchQueue.** All concurrency via async/await, Actor, Task.
5. **SwiftData for persistence.** Only `LureServerProfile` needs storage.
6. **Keychain for secrets.** Session cookies stored via `LureKeychain`.
7. **No UIKit** in views.

---

## File Structure

```
Lure/
├── LureApp.swift                              # @main entry point
├── Utilities/
│   ├── LureConstants.swift                    # TMDB URLs, MediaStatus, RequestStatus enums
│   ├── ImageURL.swift                         # TMDB image URL builder
│   └── LureKeychain.swift                     # Actor-based Keychain wrapper
├── Models/
│   ├── LureServerProfile.swift                # SwiftData @Model
│   ├── LureError.swift                        # Unified error enum
│   ├── SeerrUser.swift                        # User, quota, public settings
│   ├── SeerrMediaModels.swift                 # MovieResult, TvResult, PersonResult, MediaInfo,
│   │                                          #   MixedResult, DiscoverResponse, Genre, status helpers
│   ├── SeerrDetailModels.swift                # MovieDetail, TVDetail, Season, Credits, Cast,
│   │                                          #   Crew, Collection, Ratings, Videos, WatchProviders
│   └── SeerrRequestModels.swift               # MediaRequest, CreateRequestBody, RequestList,
│                                              #   RequestCount, DiscoverSlider, SeasonRequest
├── Services/
│   └── SeerrAPIClient.swift                   # Actor: all HTTP calls with cookie session management
├── ViewModels/
│   ├── AuthViewModel.swift                    # Login, session restore, logout
│   ├── DiscoverViewModel.swift                # Trending, popular, upcoming
│   ├── SearchViewModel.swift                  # Multi-type search with debounce
│   ├── MovieDetailViewModel.swift             # Movie info, ratings, request
│   ├── TVDetailViewModel.swift                # TV info, season selection, request
│   ├── RequestListViewModel.swift             # Request management with filters
│   └── UserProfileViewModel.swift             # User info and quota
└── Views/
    ├── ContentView.swift                      # Root: auth gate + session restore + deep link
    ├── Auth/
    │   └── LoginView.swift                    # Server URL → credentials → login
    ├── Discover/
    │   ├── DiscoverView.swift                 # Home screen with media sliders
    │   ├── MediaSliderView.swift              # Horizontal scrolling row
    │   └── TitleCardView.swift                # Compact poster card
    ├── Search/
    │   └── SearchView.swift                   # Search bar + results list
    ├── Detail/
    │   ├── MovieDetailView.swift              # Full movie detail + request button
    │   └── TVDetailView.swift                 # TV detail + season picker + request
    ├── Request/
    │   └── RequestListView.swift              # Request list with admin actions
    ├── Profile/
    │   └── UserProfileView.swift              # User info, quota, logout
    ├── Shared/
    │   ├── PosterImage.swift                  # Reusable async poster image
    │   └── StatusBadge.swift                  # Media availability badge
    └── Navigation/
        └── LureTabView.swift                  # Tab bar: Discover, Search, Requests, Profile
```

**Total: 25 files**

---

## Integration Steps

### 1. Create Xcode Project
- New → App → SwiftUI, Swift, SwiftData
- Product Name: `Lure`, Bundle ID: `com.jamesoberle.Lure`
- Deployment target: iOS 26.0

### 2. Add All Source Files
- Drag the entire directory structure into the Xcode project navigator
- All files belong to the single `Lure` target

### 3. Configure URL Scheme
In the Lure target → Info → URL Types:
- Add URL scheme: `lure`
- This enables deep links like `lure://connect?url=http://192.168.1.50:5055`

### 4. Fix Compilation Issues

**Common issues to watch for:**

- **Swift 6 Concurrency**: `SeerrAPIClient` is an actor — all calls are `await`-ed.
  ViewModels are `@Observable` classes. If Sendable warnings appear, add `@MainActor`
  to the ViewModels and Views that need it.

- **`@Bindable` pattern**: Views use `@Bindable var vm = vm` for local bindings.
  If this causes issues, switch to `@State` ownership.

- **JSONDecoder**: The Seerr API uses camelCase for most keys. The default
  JSONDecoder should work. If specific keys need mapping, add `CodingKeys`.
  Some fields like `WatchProvider` use snake_case and have explicit CodingKeys.

- **Optional handling**: Many Seerr API fields are optional (the API returns
  partial objects). All model fields that could be absent are marked optional.

- **`SeerrMixedResult.toMediaItem()`**: The discover/search endpoints return
  mixed types with a `mediaType` discriminator. This method converts to the
  `SeerrMediaItem` enum for uniform handling in views.

### 5. Navigation Architecture

The app uses a **tab-based** layout:

```
LureApp
└── ContentView (auth gate)
    ├── LoginView (not authenticated)
    └── LureTabView (authenticated)
        ├── Tab 1: DiscoverView → MovieDetailView / TVDetailView
        ├── Tab 2: SearchView → MovieDetailView / TVDetailView
        ├── Tab 3: RequestListView
        └── Tab 4: UserProfileView
```

Navigation within tabs uses `NavigationStack` with `navigationDestination(for: MediaDestination.self)`
to route to detail views. The `MediaDestination` struct carries `mediaType` + `tmdbId`.

### 6. Deep Link Support

The app supports `lure://connect?url=<seerr_url>` for easy onboarding.
`ContentView.handleDeepLink()` extracts the URL and pre-fills the server field.

For Universal Links (future), add an associated domains entitlement
and host an `apple-app-site-association` file.

---

## API Architecture

### Auth Flow
1. `GET /api/v1/settings/public` — Check server is initialized, get media server type
2. `POST /api/v1/auth/jellyfin` — Login with username/password, get session cookie
3. Cookie stored in Keychain, restored on next launch
4. `GET /api/v1/auth/me` — Validate session on restore

### Session Management
- Seerr uses `connect.sid` session cookies with 30-day TTL
- `SeerrAPIClient` attaches the cookie to every request via the `Cookie` header
- On 401/403, the user is sent back to login
- Cookie is extracted from `Set-Cookie` response header on login

### Data Flow
```
SeerrAPIClient (actor)
    ↓ called by
ViewModel (@Observable)
    ↓ observed by
View (SwiftUI)
```

ViewModels own the data and API interaction. Views observe changes via `@Observable`.
No environment injection of the API client — it's passed directly through initializers.

---

## Key API Endpoints Used

| Feature | Endpoint | Notes |
|---------|----------|-------|
| Public config | `GET /settings/public` | No auth needed, checks initialization |
| Jellyfin login | `POST /auth/jellyfin` | Returns user + session cookie |
| Current user | `GET /auth/me` | Validates session |
| Trending | `GET /discover/trending` | Mixed movie + TV results |
| Popular movies | `GET /discover/movies` | With sortBy, genre params |
| Popular TV | `GET /discover/tv` | With sortBy, genre params |
| Upcoming | `GET /discover/movies/upcoming` | |
| Search | `GET /search?query=` | Multi-type search |
| Movie detail | `GET /movie/{tmdbId}` | Full detail with mediaInfo |
| Movie ratings | `GET /movie/{tmdbId}/ratingscombined` | RT, IMDb, TMDb |
| TV detail | `GET /tv/{tmdbId}` | Full detail with seasons |
| Create request | `POST /request` | Movie or TV with seasons |
| List requests | `GET /request` | Paginated with filters |
| Request count | `GET /request/count` | Aggregate counts |
| Approve | `POST /request/{id}/approve` | Admin only |
| Decline | `POST /request/{id}/decline` | Admin only |
| Delete | `DELETE /request/{id}` | Owner or admin |
| Retry | `POST /request/{id}/retry` | Admin only, failed requests |
| User quota | `GET /user/{id}/quota` | Movie + TV quota |
| User requests | `GET /user/{id}/requests` | User's own requests |

---

## Pagination Pattern

Seerr uses `take` + `skip` (not page/pageSize):
- `take`: Number of results per page
- `skip`: Number of results to skip

Response includes `pageInfo: { pages, pageSize, results, page }`.

Discovery/search endpoints use `page` (1-indexed) with `totalPages` + `totalResults`.

---

## Test Priority

1. **Login flow**: Enter server URL → validate → enter credentials → login
2. **Discover tab**: Trending, popular movies, popular TV sliders load with posters
3. **Search**: Type a query, see mixed results
4. **Movie detail**: Tap a movie, see backdrop, info, cast, ratings
5. **TV detail**: Tap a show, see seasons
6. **Request movie**: Tap request button, verify request created
7. **Request TV**: Open season picker, select seasons, submit
8. **Request list**: See all requests, admin can approve/decline
9. **Profile**: See user info, quota, logout
10. **Deep link**: Open `lure://connect?url=http://localhost:5055` in Safari
11. **Session restore**: Kill app, relaunch, verify auto-login

---

## Future Enhancements (not in scope now)

- Universal Links for onboarding (requires web domain + AASF)
- Push notifications via Cloudflare Worker
- Plex OAuth login (alternative to Jellyfin)
- Person detail view (actor filmography)
- Collection detail view
- Watchlist management
- Issue reporting
- Genre browsing (dedicated genre pages)
- Discover slider customization
- Localization
