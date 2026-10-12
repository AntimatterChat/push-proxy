# Antimatter Push Proxy Changelog

## Antimatter
- Renamed to the Antimatter Push Proxy: the binary, the Docker image and the configuration file are
  now `antimatter-push-proxy` (`antimatter-push-proxy.json`; `mattermost-push-proxy.json` is still
  read when the new file is missing).
- The sample configuration targets the Antimatter mobile app (`chat.antimatter.app`).
- The Docker image is built from source (`docker/Dockerfile`); the FIPS image, which needed
  Mattermost's private base images, and Mattermost's release and publishing tooling are removed.
- The README explains how to run your own push proxy.

The releases below are those of the Mattermost Push Proxy this project is based on.


## 5.8.1 Release
- Release Date: March 28, 2019
- Compatible with all versions of Mattermost server and mobile

### Compatibility
 - As of April 10, 2018, Google has deprecated the Google Cloud Messaging (GCM) service. The GCM server and client APIs are deprecated and will be removed as of April 11, 2019. You must [migrate GCM apps to Firebase Cloud Messaging (FCM)](https://developers.mattermost.com/contribute/mobile/push-notifications/migrate-gcm-fcm/), which inherits the reliable and scalable GCM infrastructure, plus many new features.
 
### Bug Fixes
 - FCM messages are sent as high priority to wake Android devices in doze mode

________________

## 5.8 Release
- Release Date: March 20, 2019
- Compatible with all versions of Mattermost server and mobile

### Combatibility
 - As of April 10, 2018, Google has deprecated the Google Cloud Messaging (GCM) service. The GCM server and client APIs are deprecated and will be removed as of April 11, 2019. You must [migrate GCM apps to Firebase Cloud Messaging (FCM)](https://developers.mattermost.com/contribute/mobile/push-notifications/migrate-gcm-fcm/), which inherits the reliable and scalable GCM infrastructure, plus many new features.
 
### Highlights
 - Adds support for Firebase Cloud Messaging
