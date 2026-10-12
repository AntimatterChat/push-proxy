# Antimatter Push Proxy

The push proxy delivers the push notifications of an [Antimatter](https://antimatter.chat) server to
the Antimatter mobile app. The server never talks to Apple or Google itself: it posts each
notification to the push proxy, which holds the mobile app's credentials and forwards the
notification to Apple Push Notification service (APNs) for iOS and to Firebase Cloud Messaging (FCM)
for Android.

```
Antimatter server ──HTTPS──▶ push proxy ──▶ APNs (iOS)  ──▶ iPhone / iPad
  (System Console:                       └─▶ FCM (Android) ──▶ Android phone
   Push Notification Server)
```

It is based on the [Mattermost Push Proxy](https://github.com/mattermost/mattermost-push-proxy) and
speaks the same protocol (`POST /api/v1/send_push` and `POST /api/v1/ack`), so it works with any
Antimatter server.

- [Self-hosting](#self-hosting)
- [Configuration reference](#configuration-reference)
- [HTTP API](#http-api)
- [Building](#building)

## Self-hosting

Apple and Google only deliver a notification to an app when it is sent with that app's own
credentials: an APNs key from the Apple developer account that publishes the iOS app, and a service
account of the Firebase project the Android app was built with. A push proxy therefore works with
one build of the mobile app, the one whose credentials it holds. To run your own, you build the
mobile app with your own identifiers (see the mobile app's README) and give this proxy the matching
credentials. The steps below use the Antimatter app's identifier, `chat.antimatter.app`: replace it
with yours.

### 1. Android: a Firebase project and a service account

1. In the [Firebase console](https://console.firebase.google.com), create a project (Google Analytics
   is not needed).
2. Add an Android app to it with the package name of your build (`chat.antimatter.app`). Download the
   `google-services.json` it offers: it goes into the mobile app
   (`android/app/google-services.json`) when you build it.
3. In *Project settings > Cloud Messaging*, check that the *Firebase Cloud Messaging API (V1)* is
   enabled.
4. In *Project settings > Service accounts*, click *Generate new private key*. This downloads a JSON
   file: it is the proxy's Android credential. Keep it secret (anyone holding it can send
   notifications to your users), for example as `certs/firebase-service-account.json`.

### 2. iOS: an APNs key

1. In your [Apple Developer account](https://developer.apple.com/account), under *Certificates,
   Identifiers & Profiles > Identifiers*, make sure the App ID of your build (`chat.antimatter.app`)
   has the *Push Notifications* capability.
2. Under *Keys*, create a key with *Apple Push Notifications service (APNs)* enabled and download the
   `AuthKey_<KEY ID>.p8` file (Apple lets you download it only once). Note the *Key ID* shown next to
   it and your *Team ID* (top right of the developer site).
3. Store the `.p8` file next to the Firebase file, for example as `certs/AuthKey_ABCDE12345.p8`.

One key works for all your apps and for both the sandbox and production APNs environments, and does
not expire. Builds installed from Xcode use the sandbox environment
(`"ApplePushUseDevelopment": true`); TestFlight and App Store builds use production (`false`).

Calls ring on iOS through VoIP (PushKit) pushes. They need nothing more in the proxy: when the
server marks a notification as `transport=voip`, the proxy sends it to the `<topic>.voip` topic
with the same key. The app itself must declare the `voip` background mode.

### 3. Configure the proxy

Copy `config/antimatter-push-proxy.sample.json` to `config/antimatter-push-proxy.json` and fill in
the credentials:

```json
{
    "ListenAddress": ":8066",
    "ThrottlePerSec": 300,
    "ThrottleMemoryStoreSize": 50000,
    "ThrottleVaryByHeader": "X-Forwarded-For",
    "EnableMetrics": false,
    "SendTimeoutSec": 30,
    "RetryTimeoutSec": 8,
    "ApplePushSettings": [
        {
            "Type": "apple_rn",
            "ApplePushUseDevelopment": false,
            "ApplePushTopic": "chat.antimatter.app",
            "AppleAuthKeyFile": "./certs/AuthKey_ABCDE12345.p8",
            "AppleAuthKeyID": "ABCDE12345",
            "AppleTeamID": "FGHIJ67890"
        }
    ],
    "AndroidPushSettings": [
        {
            "Type": "android_rn",
            "ServiceFileLocation": "./certs/firebase-service-account.json"
        }
    ],
    "EnableConsoleLog": true,
    "EnableFileLog": false,
    "LogFormat": "plain",
    "LogLevel": "info"
}
```

The mobile app registers its devices as `apple_rn:<token>` and `android_rn:<token>`: each `Type`
must match. `ApplePushTopic` is the iOS bundle identifier. FCM needs no app identifier here: the
service account designates the Firebase project, and the project knows its Android apps.

To also serve a second iOS build (say, a beta with another bundle identifier), add an entry with
its own `Type` and topic: the iOS app registers as `apple_rnbeta` when its bundle identifier
contains `rnbeta`.

### 4. Run it

With Docker (the image is not published yet, so build it from this repository):

```sh
docker build -t antimatter-push-proxy -f docker/Dockerfile https://github.com/AntimatterChat/push-proxy.git
docker run -d --name push-proxy --restart unless-stopped -p 8066:8066 \
  -v "$PWD/config:/antimatter-push-proxy/config:ro" \
  -v "$PWD/certs:/antimatter-push-proxy/certs:ro" \
  antimatter-push-proxy
```

With Docker Compose, next to the Antimatter server:

```yaml
services:
  push-proxy:
    build:
      context: https://github.com/AntimatterChat/push-proxy.git
      dockerfile: docker/Dockerfile
    restart: unless-stopped
    volumes:
      - ./push-proxy/config:/antimatter-push-proxy/config:ro
      - ./push-proxy/certs:/antimatter-push-proxy/certs:ro
```

Without Docker: `make package` builds `dist/antimatter-push-proxy-<os>-<arch>.tar.gz`; unpack it,
put the config in `config/antimatter-push-proxy.json` and start `bin/antimatter-push-proxy` from the
unpacked directory (or pass `-config /path/to/antimatter-push-proxy.json`). A proxy that was set up
before the rename keeps working: when `antimatter-push-proxy.json` is missing, the proxy reads
`mattermost-push-proxy.json`.

At startup the log names each push target it initializes; a target whose credentials can't be
loaded is logged as an error and skipped. Once it runs, `curl http://localhost:8066/version`
answers.

### 5. Point the Antimatter server at it

In the System Console, go to *Environment > Push Notification Server*, choose *Send push
notifications through your own push proxy* and enter the proxy's address, then save:

- `http://push-proxy:8066` when the proxy runs in the same Docker Compose project as the server,
- `https://push.example.com` when it runs elsewhere. Put it behind a reverse proxy with HTTPS: the
  notifications may contain message text.

The same settings, in `config.json` or as environment variables:

```sh
MM_EMAILSETTINGS_SENDPUSHNOTIFICATIONS=true
MM_EMAILSETTINGS_PUSHNOTIFICATIONSERVER=http://push-proxy:8066
```

What notifications contain is chosen under *Site Configuration > Notifications > Push Notification
Contents*. *Full message content fetched from the server on receipt* keeps message text out of
Apple's and Google's services.

To check, log in with the mobile app, put it in the background and have another account mention
you. If no notification arrives, the server's log (search for `push`) and the proxy's log say
why: an unknown `Type`, a rejected key, or a device token that belongs to another app build.

The proxy does not authenticate the servers that use it. Don't expose it to the Internet unless
you mean to: keep it on a private network, or restrict who can reach it in your reverse proxy.

## Configuration reference

| Setting | Default | Meaning |
| --- | --- | --- |
| `ListenAddress` | `:8066` | Address and port to listen on. |
| `ThrottlePerSec` | `300` | Maximum requests per second, per value of `ThrottleVaryByHeader`. |
| `ThrottleMemoryStoreSize` | `50000` | Number of throttling buckets kept in memory. |
| `ThrottleVaryByHeader` | `X-Forwarded-For` | Header that identifies a client for throttling. |
| `EnableMetrics` | `false` | Serve Prometheus metrics on `/metrics`. |
| `SendTimeoutSec` | `30` | Timeout of a delivery to APNs or FCM, retries included. |
| `RetryTimeoutSec` | `8` | Timeout of a single attempt. |
| `ApplePushSettings[]` | | `Type`, `ApplePushTopic`, `ApplePushUseDevelopment`, and either an APNs key (`AppleAuthKeyFile`, `AppleAuthKeyID`, `AppleTeamID`) or a legacy certificate (`ApplePushCertPrivate` PEM file, `ApplePushCertPassword`). |
| `AndroidPushSettings[]` | | `Type` and `ServiceFileLocation` (the Firebase service account JSON file). |
| `EnableConsoleLog`, `EnableFileLog`, `LogFileLocation` | console | Where to log. |
| `LogFormat` | `plain` | `plain` or `json`. |
| `LogLevel` | `info` | `debug`, `info`, `warn` or `error`. |

Outgoing connections to APNs and FCM go through the proxy server named by the `HTTPS_PROXY` (or
`HTTP_PROXY`) environment variable, when set.

## HTTP API

| Endpoint | Description |
| --- | --- |
| `GET /` | A short page naming the service. |
| `GET /version` | Version and build hash, as JSON. |
| `POST /api/v1/send_push` | Sends a notification (sent by the Antimatter server). |
| `POST /api/v1/ack` | Records that a device received a notification (sent by the server). |
| `GET /metrics` | Prometheus metrics, when `EnableMetrics` is on. |

The OpenAPI description is in [`swagger/spec.yaml`](swagger/spec.yaml) (`npm run build` renders it).

## Building

Requires Go (see `go.mod`).

```sh
make test           # run the tests
make vet            # go vet
make build          # binaries for linux-amd64, linux-arm64 and freebsd-amd64 in ./dist
make package        # the same, packed with the sample config
make docker-build   # the Docker image, built from source
make lint           # golangci-lint and hadolint (in Docker)
```

## License

Apache License 2.0, see [LICENSE.txt](LICENSE.txt) and [NOTICE.txt](NOTICE.txt). Based on the
Mattermost Push Proxy, © Mattermost, Inc.
