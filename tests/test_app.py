import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import app


BASE_FORWARD = {
    "source": "live",
    "destination": "rtmp://example.test/live/key",
    "audio_index": 2
}


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


if __name__ == "__main__":
    unittest.main()
