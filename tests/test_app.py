import json
import os
import tempfile
import unittest
from unittest import mock

import app


BASE_FORWARD = {
    "source": "live",
    "destination": "rtmp://example.test/live/key",
    "audio_index": 2
}


class AuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.client = app.app.test_client()

    def test_unauthenticated_access(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 302)
        self.assertIn("/login", response.headers["Location"])
        response = self.client.get("/api/forwards")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.get_json(), {"ok": False, "error": "Unauthorized"})

    def test_login_get_and_valid_form(self):
        self.assertEqual(self.client.get("/login").status_code, 200)
        response = self.client.post("/login", data={
            "username": app.DASHBOARD_USER, "password": app.DASHBOARD_PASS
        })
        self.assertEqual(response.status_code, 302)
        with self.client.session_transaction() as session:
            self.assertTrue(session["logged_in"])
            self.assertEqual(session["username"], app.DASHBOARD_USER)

    def test_login_json_and_invalid_credentials(self):
        response = self.client.post("/login", json={
            "username": app.DASHBOARD_USER, "password": app.DASHBOARD_PASS
        })
        self.assertEqual(response.get_json(), {"ok": True})
        client = app.app.test_client()
        response = client.post("/login", json={"username": "bad", "password": "bad"})
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.get_json()["error"], "Invalid username or password")

    def test_logout_clears_session(self):
        with self.client.session_transaction() as session:
            session["logged_in"] = True
            session["username"] = "admin"
        response = self.client.get("/logout")
        self.assertEqual(response.status_code, 302)
        self.assertIn("/login", response.headers["Location"])
        with self.client.session_transaction() as session:
            self.assertNotIn("logged_in", session)


class SrtPortApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app.app.test_client()
        with self.client.session_transaction() as session:
            session["logged_in"] = True

    @mock.patch.object(app.requests, "get")
    def test_get_srt_port(self, get):
        get.return_value.json.return_value = {"srtAddress": "0.0.0.0:9000"}
        response = self.client.get("/api/srt/port")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["port"], 9000)
        get.assert_called_once_with(f"{app.MEDIAMTX_API}/v3/config/global/get", timeout=2.0)

    @mock.patch.object(app.requests, "patch")
    def test_post_srt_port(self, patch):
        with mock.patch.object(app, "MEDIAMTX_CONF", "/nonexistent/mediamtx.yml"):
            response = self.client.post("/api/srt/port", json={"port": 9001})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["port"], 9001)
        patch.assert_called_once_with(f"{app.MEDIAMTX_API}/v3/config/global/patch",
                                      json={"srtAddress": ":9001"}, timeout=3.0)

    def test_post_rejects_invalid_ports(self):
        for port in (1023, 65536, "not-a-port"):
            with self.subTest(port=port):
                response = self.client.post("/api/srt/port", json={"port": port})
                self.assertEqual(response.status_code, 400)
                self.assertFalse(response.get_json()["ok"])


class AudioTrackTests(unittest.TestCase):
    def test_audio_mapping_is_preserved(self):
        command = app.build_ffmpeg_command(dict(BASE_FORWARD, mode="copy"))
        self.assertIn("0:v:0?", command)
        self.assertIn("0:a:2?", command)

    def test_audio_index_validation(self):
        self.assertEqual(app.validate_audio_index("3"), 3)
        for value in (-1, 64, "1.5", "1;touch /tmp/x", True):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    app.validate_audio_index(value)

    def test_parse_audio_streams(self):
        streams = app.parse_audio_streams({"streams": [
            {"index": 0, "codec_type": "video"},
            {"index": 1, "codec_type": "audio", "codec_name": "aac", "channels": 2,
             "tags": {"language": "eng"}}
        ]})
        self.assertEqual(streams[0]["selector"], 0)
        self.assertEqual(streams[0]["stream_index"], 1)
        self.assertEqual(streams[0]["language"], "eng")


class ProcessingTests(unittest.TestCase):
    def test_copy_ignores_bitrate_values_and_flags(self):
        command = app.build_ffmpeg_command(dict(
            BASE_FORWARD, mode="copy", video_bitrate="malformed", encoder_preset="bad"
        ))
        self.assertIn("copy", command)
        for flag in ("-b:v", "-maxrate", "-bufsize", "-b:a", "-preset"):
            self.assertNotIn(flag, command)

    def test_custom_emits_exact_processing_flags_without_scaling(self):
        command = app.build_ffmpeg_command(dict(
            BASE_FORWARD, mode="custom", video_bitrate=4200, max_bitrate=4800,
            buffer_size=8400, audio_bitrate=192, encoder_preset="fast"
        ))
        expected = ["-c:v", "libx264", "-preset", "fast", "-b:v", "4200k",
                    "-maxrate", "4800k", "-bufsize", "8400k", "-c:a", "aac",
                    "-b:a", "192k"]
        start = command.index("-c:v")
        self.assertEqual(command[start:start + len(expected)], expected)
        self.assertNotIn("-s", command)
        self.assertNotIn("-r", command)

    def test_custom_and_legacy_defaults(self):
        self.assertEqual(app.processing_settings({"mode": "custom"}), dict(
            mode="custom", video_bitrate=4500, max_bitrate=5000,
            buffer_size=9000, audio_bitrate=160, encoder_preset="veryfast"))
        legacy = app.processing_settings({"mode": "transcode_720p"})
        self.assertEqual((legacy["video_bitrate"], legacy["max_bitrate"],
                          legacy["buffer_size"], legacy["audio_bitrate"]),
                         (2500, 3000, 5000, 128))

    def test_ranges_and_relationship(self):
        cases = [
            ("video_bitrate", 249), ("video_bitrate", 50001),
            ("max_bitrate", 249), ("max_bitrate", 50001),
            ("buffer_size", 499), ("buffer_size", 100001),
            ("audio_bitrate", 31), ("audio_bitrate", 513)
        ]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                data = dict(app.TRANSCODE_DEFAULTS, mode="custom")
                data[field] = value
                with self.assertRaises(ValueError):
                    app.processing_settings(data)
        with self.assertRaisesRegex(ValueError, "greater than or equal"):
            app.processing_settings(dict(app.TRANSCODE_DEFAULTS, mode="custom",
                                         video_bitrate=5000, max_bitrate=4999))

    def test_malformed_numbers_modes_and_preset(self):
        for field, value in (("video_bitrate", "4500k"), ("audio_bitrate", 128.5)):
            data = dict(app.TRANSCODE_DEFAULTS, mode="custom")
            data[field] = value
            with self.assertRaises(ValueError):
                app.processing_settings(data)
        with self.assertRaises(ValueError):
            app.processing_settings({"mode": "anything"})
        with self.assertRaises(ValueError):
            app.processing_settings(dict(app.TRANSCODE_DEFAULTS, mode="custom",
                                         encoder_preset="veryfast;touch /tmp/x"))
        for preset in app.ALLOWED_ENCODER_PRESETS:
            settings = app.processing_settings(dict(app.TRANSCODE_DEFAULTS, mode="custom",
                                                    encoder_preset=preset))
            self.assertEqual(settings["encoder_preset"], preset)


class ForwardApiTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.data_file = os.path.join(self.temp_dir.name, "forwards.json")
        self.data_patch = mock.patch.object(app, "DATA_FILE", self.data_file)
        self.start_patch = mock.patch.object(app, "start_relay")
        self.data_patch.start()
        self.start_mock = self.start_patch.start()
        app.save_forwards([])
        self.client = app.app.test_client()
        with self.client.session_transaction() as session:
            session["logged_in"] = True
            session["username"] = "admin"

    def tearDown(self):
        self.start_patch.stop()
        self.data_patch.stop()
        self.temp_dir.cleanup()

    def test_custom_settings_are_persisted_and_returned(self):
        payload = dict(BASE_FORWARD, name="Test", mode="custom", video_bitrate=3000,
                       max_bitrate=3500, buffer_size=6000, audio_bitrate=128,
                       encoder_preset="faster")
        response = self.client.post("/api/forwards", json=payload)
        self.assertEqual(response.status_code, 200)
        saved = app.load_forwards()[0]
        self.assertEqual(saved["video_bitrate"], 3000)
        returned = self.client.get("/api/forwards").get_json()[0]
        self.assertEqual(returned["encoder_preset"], "faster")
        self.assertIn("3000/3500k", returned["processing_summary"])
        self.assertEqual(returned["destination_label"], "rtmp://example.test")
        self.assertNotIn("key", returned["destination_label"])

    def test_api_rejects_invalid_processing(self):
        for change in ({"mode": "invalid"}, {"mode": "custom", "video_bitrate": "x"},
                       {"mode": "custom", "video_bitrate": 5000, "max_bitrate": 4000},
                       {"mode": "custom", "encoder_preset": "placebo"}):
            payload = dict(BASE_FORWARD, **change)
            response = self.client.post("/api/forwards", json=payload)
            self.assertEqual(response.status_code, 400)
            self.assertIn("error", response.get_json())


class PreviewSecurityTests(unittest.TestCase):
    def tearDown(self):
        app.stop_preview()

    def test_stream_id_and_path_validation(self):
        for valid in ("Makasna", "cam-1", "room_2.main"):
            self.assertEqual(app.validate_stream_id(valid), valid)
        for invalid in ("", "../secret", "a/b", "http://host/x", "x?query=1", "a" * 65, None):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                app.validate_stream_id(invalid)
        with self.assertRaises(ValueError):
            app.preview_directory("../bad")

    def test_preview_command_mapping_and_bounded_hls(self):
        command = app.build_preview_command("Makasna", 3, "/tmp/preview")
        self.assertIn("rtsp://127.0.0.1:8554/Makasna", command)
        self.assertIn("0:v:0?", command)
        self.assertIn("0:a:3?", command)
        self.assertEqual(command[command.index("-hls_list_size") + 1], "5")
        self.assertIn("delete_segments+append_list+omit_endlist+independent_segments", command)
        self.assertNotIn("shell=True", command)

    @mock.patch.object(app.threading, "Thread")
    @mock.patch.object(app.threading, "Timer")
    @mock.patch.object(app.subprocess, "Popen")
    def test_start_replaces_and_stop_terminates(self, popen, timer, thread):
        first, second = mock.Mock(), mock.Mock()
        first.poll.return_value = None
        second.poll.return_value = None
        popen.side_effect = [first, second]
        with tempfile.TemporaryDirectory() as root, mock.patch.object(app, "PREVIEW_ROOT", root):
            app.start_preview("Makasna", 0)
            app.start_preview("Makasna", 1)
            first.terminate.assert_called_once()
            app.stop_preview()
            second.terminate.assert_called_once()
        self.assertFalse(popen.call_args.kwargs["shell"])


class SrtHealthTests(unittest.TestCase):
    def test_exact_publish_correlation_and_sanitization(self):
        record = {"path": "Makasna", "state": "publish", "remoteAddr": "secret",
                  "mbpsReceiveRate": 8.5, "msRTT": 40, "packetsReceivedLoss": 2,
                  "packetsReceivedLossRate": 0.1, "packetsReceivedRetrans": 3,
                  "packetsReceivedDrop": 0, "bytesReceivedDrop": 0,
                  "mbpsLinkCapacity": 20, "packetsReceived": 100,
                  "packetsReceivedUnique": 95, "bytesReceived": 1000,
                  "bytesReceivedLoss": 10}
        metrics = app.find_srt_publisher({"items": [record]}, "Makasna")
        self.assertEqual(metrics["health"], "healthy")
        self.assertNotIn("remoteAddr", metrics)
        self.assertIsNone(app.find_srt_publisher({"items": [record]}, "makasna"))
        record["state"] = "read"
        self.assertIsNone(app.find_srt_publisher({"items": [record]}, "Makasna"))

    def test_deterministic_thresholds(self):
        self.assertEqual(app.classify_srt_health(149, .49, 0), "healthy")
        self.assertEqual(app.classify_srt_health(150, 0, 0), "degraded")
        self.assertEqual(app.classify_srt_health(0, .5, 0), "degraded")
        self.assertEqual(app.classify_srt_health(300, 0, 0), "critical")
        self.assertEqual(app.classify_srt_health(0, 2, 0), "critical")
        self.assertEqual(app.classify_srt_health(0, 0, 100), "critical")


class DashboardFlowTests(unittest.TestCase):
    def setUp(self):
        self.client = app.app.test_client()
        with self.client.session_transaction() as session:
            session["logged_in"] = True
            session["username"] = "admin"

    def test_new_relay_flow_markers(self):
        html = self.client.get("/").get_data(as_text=True)
        for marker in ("Add Redirect Target", "New Forward Target", "Target Label / Name",
                       "Source Stream Name / URL", "Detect Audio Tracks",
                       "Preset / Destination Type", "Destination URL / Stream Target",
                       "Direct Stream Copy", "Custom Bitrate", "Save &amp; Start",
                       "add-form-error", "applyPreset", "detectAudioTracks",
                       "e.target===e.currentTarget"):
            with self.subTest(marker=marker):
                self.assertIn(marker, html)
        self.assertNotIn("font-awesome", html.lower())
        self.assertNotIn("fa-solid", html)
        self.assertNotIn("RustDesk", html)

    @mock.patch.object(app, "probe_audio_streams", return_value=[])
    def test_audio_detection_accepts_source_flow(self, probe):
        response = self.client.post("/api/audio-tracks", json={"source": "rtmp://example.test/live"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["source"], "rtmp://example.test/live")
        probe.assert_called_once_with("rtmp://example.test/live")


class PreviewApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app.app.test_client()
        with self.client.session_transaction() as session:
            session["logged_in"] = True
            session["username"] = "admin"

    def test_rejects_malformed_start(self):
        response = self.client.post("/api/preview/start", json={"stream_id": "../x", "audio_index": 0})
        self.assertEqual(response.status_code, 400)
        self.assertFalse(response.get_json()["ok"])

    @mock.patch.object(app, "start_preview", return_value="a" * 32)
    def test_start_schema(self, start):
        response = self.client.post("/api/preview/start", json={"stream_id": "Makasna", "audio_index": 2})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["audio_index"], 2)
        start.assert_called_once_with("Makasna", 2)

    @mock.patch.object(app.requests, "get", side_effect=app.requests.Timeout())
    def test_srt_api_failure_is_sanitized(self, get):
        response = self.client.get("/api/srt-health?stream_id=Makasna")
        self.assertEqual(response.status_code, 503)
        body = response.get_json()
        self.assertFalse(body["ok"])
        self.assertNotIn("127.0.0.1", body["error"])

    def test_preview_file_rejects_bad_paths(self):
        response = self.client.get("/preview/not-a-token/index.m3u8")
        self.assertEqual(response.status_code, 404)


if __name__ == "__main__":
    unittest.main()
