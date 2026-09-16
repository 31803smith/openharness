# Development

## Repository layout

```
desktop/    the app (Flutter; macOS and Linux). third_party/xterm is the patched terminal core
cli/        the harness daemon and CLI (TypeScript, one bundle). src/engines/ is one folder per engine
backend/    the relay (Node, Prisma/MongoDB, Redis)
provider/   the API-provider spec, reference and example providers, conformance runner
device/     firmware for the Harness device (ESP-IDF, esp32-circle)
dsh/        domain harnesses: the contract and schemas, the registry, the starter, daemon-level tools
```

## Build and test

```bash
# cli
cd cli && npm install && npm run typecheck && npm test
make install-cli          # bundle this tree into ~/.harness/cli and restart the daemon on it

# desktop (Flutter ≥ 3.47 / Dart ≥ 3.13; SPM on for macOS)
cd desktop && flutter pub get && flutter analyze && flutter test
flutter run -d macos      # or -d linux

# backend
cd backend && npm install && npm run typecheck && npm test

# provider
cd provider/e2e && npm install && npm test

# device
make device-test
```

Each product releases on its own tag and the suffix routes the workflow: `vX.Y.Z_cli` bundles and
publishes the daemon (running daemons pick it up within a minute), `vX.Y.Z_backend` builds the image,
`vX.Y.Z_desktop` builds, signs and publishes both macOS bundles and both Linux architectures.
`make release-cli|release-backend|release-desktop` cut them; `make upload-circle` publishes device
firmware over the air. `ci.yml` runs the CLI suite on demand (Actions -> CI -> Run workflow) and holds
no secrets, which is what lets it run on a fork's branch.
`make remote-machine`
brings up a second machine in Docker so the remote path can be exercised from one laptop.
