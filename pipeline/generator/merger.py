#!/usr/bin/env python3
"""
Task 13 — Platform Defaults Merger
Deep-merges platform defaults with application-specific infra.yaml.

Merge strategy:
- For dicts: recursively merge (team values override defaults)
- For lists: team list replaces defaults list (no append)
- None values preserve defaults
"""
import pathlib
import yaml
from typing import Any, Dict

DEFAULTS_DIR = pathlib.Path(__file__).parents[2] / "platform" / "defaults"


def deep_merge(defaults: Dict[str, Any], overrides: Dict[str, Any]) -> Dict[str, Any]:
    """
    Recursively merge overrides into defaults.
    - Dicts merge recursively
    - Lists are replaced (not appended)
    - Non-dict, non-list values: override replaces default
    - None values in override preserve default
    """
    result = defaults.copy()
    
    for key, override_value in overrides.items():
        if override_value is None:
            # None explicitly means "use default"
            continue
        
        if key not in result:
            # Key doesn't exist in defaults, add it
            result[key] = override_value
        elif isinstance(result[key], dict) and isinstance(override_value, dict):
            # Both are dicts, recursively merge
            result[key] = deep_merge(result[key], override_value)
        else:
            # Override value replaces default (including list replacement)
            result[key] = override_value
    
    return result


def merge(infra: dict, env: str) -> dict:
    """
    Load platform defaults for the environment and merge with app infra.yaml.
    """
    defaults_path = DEFAULTS_DIR / f"{env}.yaml"
    
    if not defaults_path.exists():
        raise FileNotFoundError(f"Defaults file not found: {defaults_path}")
    
    with open(defaults_path) as f:
        defaults = yaml.safe_load(f) or {}
    
    merged = deep_merge(defaults, infra or {})
    return merged
