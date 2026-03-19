"""Tests for configuration management."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import pytest

from cap_inspector.core.config import AppConfig, EncoderDefaults, ScaleConfig


class TestDefaults:
    def test_encoder_defaults(self):
        enc = EncoderDefaults()
        assert enc.freq_div == 400
        assert enc.avg_count == 16
        assert enc.mode == 1

    def test_scale_defaults(self):
        sc = ScaleConfig()
        assert sc.pitch_um == 2000.0
        assert sc.counts_per_pitch == 4096
        assert sc.unit == 'mm'

    def test_app_defaults(self):
        cfg = AppConfig()
        assert cfg.encoder.freq_div == 400
        assert cfg.scale.pitch_um == 2000.0
        assert cfg.last_port == ''
        assert cfg.data_logging is False


class TestSaveLoad:
    def test_roundtrip(self, tmp_path: Path):
        # Create config
        cfg = AppConfig(
            encoder=EncoderDefaults(freq_div=800, avg_count=32, mode=2),
            scale=ScaleConfig(pitch_um=1000.0, counts_per_pitch=4096, unit='inch'),
            last_port='COM3',
            data_logging=True,
        )

        # Save
        config_file = tmp_path / 'config.json'

        import cap_inspector.core.config as config_mod
        original_dir = config_mod.CONFIG_DIR
        original_file = config_mod.CONFIG_FILE
        config_mod.CONFIG_DIR = tmp_path
        config_mod.CONFIG_FILE = config_file

        try:
            cfg.save()
            assert config_file.exists()

            # Load
            loaded = AppConfig.load()
            assert loaded.encoder.freq_div == 800
            assert loaded.encoder.avg_count == 32
            assert loaded.encoder.mode == 2
            assert loaded.scale.pitch_um == 1000.0
            assert loaded.scale.unit == 'inch'
            assert loaded.last_port == 'COM3'
            assert loaded.data_logging is True
        finally:
            config_mod.CONFIG_DIR = original_dir
            config_mod.CONFIG_FILE = original_file

    def test_load_missing_file(self, tmp_path: Path):
        import cap_inspector.core.config as config_mod
        original_file = config_mod.CONFIG_FILE
        config_mod.CONFIG_FILE = tmp_path / 'nonexistent.json'

        try:
            cfg = AppConfig.load()
            assert cfg.encoder.freq_div == 400  # Default
        finally:
            config_mod.CONFIG_FILE = original_file

    def test_load_corrupt_json(self, tmp_path: Path):
        config_file = tmp_path / 'config.json'
        config_file.write_text('not valid json {{{')

        import cap_inspector.core.config as config_mod
        original_file = config_mod.CONFIG_FILE
        config_mod.CONFIG_FILE = config_file

        try:
            cfg = AppConfig.load()
            assert cfg.encoder.freq_div == 400  # Falls back to default
        finally:
            config_mod.CONFIG_FILE = original_file

    def test_partial_load(self, tmp_path: Path):
        """Load a config file that only has some fields."""
        config_file = tmp_path / 'config.json'
        config_file.write_text(json.dumps({
            'encoder': {'freq_div': 600},
            'last_port': 'COM5',
        }))

        import cap_inspector.core.config as config_mod
        original_file = config_mod.CONFIG_FILE
        config_mod.CONFIG_FILE = config_file

        try:
            cfg = AppConfig.load()
            assert cfg.encoder.freq_div == 600
            assert cfg.encoder.avg_count == 16  # Default for missing
            assert cfg.last_port == 'COM5'
        finally:
            config_mod.CONFIG_FILE = original_file
