# Conference Note AI

Dark, animated SwiftUI iOS app paired with a Node.js + PostgreSQL backend (Heroku-ready) to record talks, capture slide photos, auto-align them to transcript timestamps, and surface AI-style summaries and study resources.

## Palette (dark theme)
- background `#452829`
- surface `#57595B`
- textPrimary `#F3E8DF`
- textSecondary `#E8D1C5`
- accent `#E8D1C5`
- accentSoft `#F3E8DF` (low opacity)
- border `#E8D1C5` (low opacity)
- destructive: soft red tint

## Repository structure
```
backend/                Express + pg server
  src/
    server.js           Entrypoint
    db.js               Pool helper
    routes/             auth, sessions, study endpoints
    services/           mock AI + alignment helpers
    middleware/         JWT auth
  migrations/001_init.sql
  Procfile              Heroku web entry
ios/
  project.yml           XcodeGen config for an iOS 17 SwiftUI app
  ConferenceNoteAI/     Sources grouped by Models, ViewModels, Services, Theme, Views
  ConferenceNoteAI/Resources/Info.plist
```

## Backend
Prereqs: Node 18+, PostgreSQL. If `OPENAI_API_KEY` is set, the backend will transcribe audio + generate summaries via OpenAI; otherwise it falls back to the offline stub in `src/services/aiMock.js`.

### New environment variables
- `OPENAI_CHAT_MODEL` (default `gpt-4o`)
- `OPENAI_EMBED_MODEL` (default `text-embedding-3-small`)
- `OPENAI_TIMEOUT_MS` (increase for longer recordings; 1-hour talks may require higher timeouts)
- `GOOGLE_SEARCH_API_KEY` + `GOOGLE_SEARCH_CX` (Google Custom Search JSON API for further reading links)
- `GOOGLE_SEARCH_MAX_RESULTS` (default 5)
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_SECURE` (SMTP email sharing)
- `APP_DEEP_LINK_BASE` (optional; defaults to `conferencenoteai://share`)

### Setup & run locally
```bash
cd backend
cp .env.example .env   # set DATABASE_URL, JWT_SECRET
npm install
npm run migrate        # runs all migrations in backend/migrations
npm start              # or npm run dev
```
Health check: `curl http://localhost:4000/health` → `{"status":"ok"}`.

### Key endpoints
- `POST /api/auth/register { email, password }`
- `POST /api/auth/login { email, password }`
- `GET /api/sessions` — list user sessions
- `POST /api/sessions { title?, eventName? }` — starts a session (status=recording)
- `GET /api/sessions/:id` — includes photos (aligned), transcript, summary, resources
- `POST /api/sessions/:id/audio { audioBase64, fileName?, mimeType?, durationSeconds }` — uploads audio bytes, marks processing, kicks off pipeline
- `POST /api/sessions/:id/photos { fileUrl, takenAtSeconds, ocrText? }`
- `POST /api/sessions/:id/chat { message, language?, include_external_reading? }` — session-scoped chat with citations
- `POST /api/sessions/:id/resummarize { speaker_metadata, topic_context, language? }`
- `POST /api/sessions/:id/reindex` — rebuild transcript chunks/embeddings
- `POST /api/sessions/:id/share { scope }` — returns app deep link
- `POST /api/sessions/:id/share/email { emails[], message?, scope }`
- `GET /api/shares/:token` — fetch shared payload (auth required)
- `POST /api/shares/:token/import` — import shared session (auth required)
- `GET /api/study` — ready sessions only

### Processing pipeline
`kickoffProcessing` in `src/routes/sessions.js` runs transcription + summary/highlights generation. With `OPENAI_API_KEY` set it calls OpenAI; otherwise it uses the mock generators in `src/services/aiMock.js`.

Photo→transcript alignment happens in `services/alignment.js` (timestamp-based).

### Deploying to Heroku
```bash
heroku create conference-note-ai
heroku addons:create heroku-postgresql:mini
heroku config:set NODE_ENV=production JWT_SECRET=change-me
# DATABASE_URL is auto-set by the addon
cd backend
heroku config:set -a conference-note-ai
git push heroku main   # or deploy via CI; Procfile is included
# run migration
heroku run -a conference-note-ai "npm run migrate"
```
If deploying from a monorepo, push `backend` as a subtree or set the Heroku app to use `backend/` as the root (e.g., via `heroku buildpacks:set -a app heroku/nodejs` and `heroku config:set NPM_CONFIG_PREFIX=backend`).

## iOS app (SwiftUI, MVVM, async/await, iOS 17+)
Sources live in `ios/ConferenceNoteAI/`. A theme system is in `Theme/` and reused everywhere. Animations: pulsing record button, staggered cards, smooth fades/scales for photos and transcript segments.

### Opening the project
Option 1 (XcodeGen):
```bash
brew install xcodegen # if not installed
cd ios
xcodegen generate
open ConferenceNoteAI.xcodeproj
```
Option 2: Create a new SwiftUI iOS 17 project in Xcode, set the bundle ID you want, then replace the auto-generated `App`, `ContentView`, and supporting files with everything under `ios/ConferenceNoteAI/` (keep `Info.plist` from `Resources/`).

### Configuring the API base URL
Edit `Services/APIClient.swift` and point `baseURL` to your deployed backend (`https://<heroku-app>.herokuapp.com`). JWT is persisted via `KeychainStorage` (`ConferenceNoteAI.jwt`).

### Offline mode (local cache + sync queue)
- View sessions offline after they have been loaded at least once.
- Record sessions offline; uploads/transcription/summarization sync when back online.
- Sync state appears on session cards and detail view; tap “Retry sync” on errors.
- To test: disable network, record a session, stop, re-enable network, then open the session detail to confirm it syncs.

### Permissions
`Info.plist` already includes microphone/camera/photo-library descriptions for AVFoundation and Photos access.

### Major view models
- `SessionListViewModel` — loads sessions for “Home”
- `RecordingViewModel` — manages AVAudioRecorder lifecycle, photo captures, uploads
- `SessionDetailViewModel` — pulls full session detail + manages full-screen photos
- `StudyViewModel` — shows “Study” tab (ready sessions)
- `AuthViewModel` — register/login + token storage

### Interaction highlights
- Home cards slide/fade in; press states via scale/opacity.
- Recording screen: pulsing record button, timer ticks, camera button bounce, thumbnail strip animates in.
- Session detail: sections fade/slide, transcript segments show inline thumbnails; tap zooms to full-screen viewer with overlays.
- Study tab: staggered card entrances, subtle elevation on press.

## AI integration hooks
Replace the mock generators in `backend/src/services/aiMock.js` with real providers. Keep outputs compatible with existing DB columns (`transcript_segments`, `summaries`, `resources`). The iOS app consumes the same shapes (snake_case → camelCase decoding is already handled).

## Assumptions & notes
- AVFoundation code is set up for single-track speech recording; background recording may require enabling Background Modes in the Xcode project (Audio, AirPlay, and Picture in Picture).
- Camera capture in-app uses `PhotosPicker` for simplicity; swap in a custom `AVCaptureSession` if you need a true in-app camera UI.
- File uploads currently send local file URLs as placeholders; replace with real upload endpoints or presigned URLs when wiring storage.
- Database migrations are idempotent for repeated local runs. Ensure the `uuid-ossp` extension is enabled on your Postgres instance.
- Share links are app-only deep links (default scheme `conferencenoteai://share?token=...`).

## Quick start (full stack)
1) Start backend locally (`backend/` instructions above).
2) Generate/open the iOS project, set `APIClient.baseURL` to your backend, run on iOS 17 simulator/device.
3) Register, start a session, record audio, capture photos, stop to trigger processing, then review in Session Detail and Study tabs.

## Testing
Backend unit tests:
```bash
cd backend
npm test
```
Integration tests (requires a test database and migrations applied):
```bash
TEST_DATABASE_URL=postgres://... npm test
```
