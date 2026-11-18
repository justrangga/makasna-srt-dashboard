# Master Deck ISO Recorder and Cloud Sync

The dashboard can create route-associated ISO recordings. Recording capacity depends on the input bitrate, selected format, retention period, and storage volume.

## Before recording

- Confirm the source is stable in the ingest monitor.
- Ensure the service user can write to the configured recordings directory.
- Confirm free disk capacity before starting.
- Test a short recording and open the resulting file before relying on a production event.

## Stop safely

Use the dashboard stop control and wait for the process to exit. Avoid killing FFmpeg with `SIGKILL`; containers such as MP4/MOV can be left without a final index.

## Cloud credentials

Cloud-sync configuration can contain service-account credentials. Keep it outside Git, protect it with restrictive permissions, and rotate it if exposed. Cloud sync is optional and should be tested separately from the live transport path.
