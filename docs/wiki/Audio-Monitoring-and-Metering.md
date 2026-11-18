# Audio Monitoring and Metering

The dashboard displays audio metering for supported live inputs and can use FFmpeg audio handling for destinations that require AAC, such as many RTMP/FLV endpoints.

## Operational guidance

- Prefer AAC, 48 kHz, stereo, and a fixed 128–192 kbps bitrate for broad compatibility.
- Maintain headroom: sustained full-scale audio risks clipping after downstream processing.
- Verify codec and channel layout with a test contribution before a live event.
- When a destination rejects copy-mode audio, configure the route to transcode only the audio where possible; copying video avoids unnecessary CPU load.

Metrics are an operator aid, not a calibration substitute. Use calibrated monitoring for compliance-critical loudness workflows.
