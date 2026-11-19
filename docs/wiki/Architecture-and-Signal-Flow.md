# Architecture and Signal Flow

## Components

- **MediaMTX** accepts SRT, RTMP, and RTSP contributions and exposes local status through its API.
- **Makasna Dashboard** authenticates operators, displays telemetry, stores route definitions, and supervises FFmpeg route processes.
- **FFmpeg** relays, fan-outs, remuxes, and transcodes when required.
- **SLS** is optional. It serves a multi-client SRT TV Pool for receivers that cannot provide an SRT Stream ID.

## Normal signal path

```text
Field encoder -> SRT publish:STREAM -> MediaMTX :8890
MediaMTX -> Dashboard telemetry via localhost :9997
Dashboard route -> FFmpeg -> receiver/CDN/SLS
SLS :12105 -> many caller-mode hardware receivers
```

## Boundary rules

The dashboard is not a replacement for MediaMTX. MediaMTX must be installed, running, and reachable on the configured local API address before route monitoring works. SLS is also independent: installing the dashboard does not create an SLS binary or service.

Keep the MediaMTX API on localhost and use the dashboard or a protected reverse proxy for operator access.
