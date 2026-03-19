"""Configuration management for Cap-Scale Inspector."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

CONFIG_DIR = Path.home() / '.cap-scale'
CONFIG_FILE = CONFIG_DIR / 'config.json'


@dataclass
class EncoderDefaults:
    freq_div: int = 400         # 200 kHz excitation
    avg_count: int = 16
    mode: int = 1               # 1=position, 2=diagnostics


@dataclass
class ScaleConfig:
    pitch_um: float = 2000.0    # Electrode pitch in micrometers
    counts_per_pitch: int = 4096
    unit: str = 'mm'            # mm, um, inch


@dataclass
class AppConfig:
    encoder: EncoderDefaults = field(default_factory=EncoderDefaults)
    scale: ScaleConfig = field(default_factory=ScaleConfig)
    last_port: str = ''
    data_logging: bool = False

    def save(self) -> None:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        data = asdict(self)
        CONFIG_FILE.write_text(json.dumps(data, indent=2))

    @classmethod
    def load(cls) -> AppConfig:
        if not CONFIG_FILE.exists():
            return cls()
        try:
            data = json.loads(CONFIG_FILE.read_text())
            enc = EncoderDefaults(**data.get('encoder', {}))
            sc = ScaleConfig(**data.get('scale', {}))
            return cls(
                encoder=enc,
                scale=sc,
                last_port=data.get('last_port', ''),
                data_logging=data.get('data_logging', False),
            )
        except (json.JSONDecodeError, TypeError, KeyError):
            return cls()
