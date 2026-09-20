#!/usr/bin/env python3
"""
Task 13 — Regulatory Enforcer
Overrides fields that app teams cannot change (security/compliance locks).

Locked fields are enforced regardless of app infra.yaml values:
- encryption.at_rest = true (always)
- encryption.in_transit = true (always)
- logging.cloudtrail = enabled (always)
- For environment == prod:
  - databases[*].deletion_protection = true
  - databases[*].multi_az = true
  - databases[*].backup_retention_days = max(35, provided_value)
"""
from typing import Any, Dict, List


def get_nested(obj: Dict, path: str, default: Any = None) -> Any:
    """
    Get a nested value using dot notation (e.g., 'encryption.at_rest').
    Handles list indices like 'databases.0.name'.
    """
    keys = path.split(".")
    current = obj
    
    for key in keys:
        if current is None:
            return default
        
        # Try to parse as integer (list index)
        try:
            idx = int(key)
            if isinstance(current, list) and 0 <= idx < len(current):
                current = current[idx]
            else:
                return default
        except ValueError:
            # Not an integer, treat as dict key
            if isinstance(current, dict):
                current = current.get(key)
            else:
                return default
    
    return current


def set_nested(obj: Dict, path: str, value: Any) -> None:
    """
    Set a nested value using dot notation, creating intermediate dicts as needed.
    """
    keys = path.split(".")
    current = obj
    
    # Navigate to parent
    for key in keys[:-1]:
        try:
            idx = int(key)
            if not isinstance(current, list):
                current = []
            while len(current) <= idx:
                current.append({})
            current = current[idx]
        except ValueError:
            if key not in current:
                current[key] = {}
            current = current[key]
    
    # Set the final value
    final_key = keys[-1]
    try:
        idx = int(final_key)
        if isinstance(current, list):
            while len(current) <= idx:
                current.append(None)
            current[idx] = value
    except ValueError:
        current[final_key] = value


def enforce(merged: dict, env: str = "prod") -> dict:
    """
    Enforce locked fields based on environment.
    Returns a new dict with enforced overrides.
    """
    enforced = merged.copy()
    
    # Global locks (apply to all environments)
    if "encryption" not in enforced:
        enforced["encryption"] = {}
    enforced["encryption"]["at_rest"] = True
    enforced["encryption"]["in_transit"] = True
    
    if "logging" not in enforced:
        enforced["logging"] = {}
    enforced["logging"]["cloudtrail"] = "enabled"
    
    # Production-specific locks
    if env == "prod":
        if "databases" not in enforced:
            enforced["databases"] = []
        
        if isinstance(enforced["databases"], list):
            for i, db in enumerate(enforced["databases"]):
                if isinstance(db, dict):
                    # Force deletion protection in prod
                    enforced["databases"][i]["deletion_protection"] = True
                    # Force multi-AZ in prod
                    enforced["databases"][i]["multi_az"] = True
                    # Enforce minimum backup retention (35 days for BNM compliance)
                    current_retention = db.get("backup_retention_days", 35)
                    enforced["databases"][i]["backup_retention_days"] = max(
                        35, int(current_retention) if current_retention else 35
                    )
    
    # Verify required tags
    if "tags" in enforced and isinstance(enforced["tags"], dict):
        required_tags = [
            "Environment",
            "Team",
            "CostCentre",
            "DataClassification",
        ]
        missing_tags = [
            tag for tag in required_tags if tag not in enforced["tags"]
        ]
        if missing_tags:
            raise ValueError(f"Missing required tags: {', '.join(missing_tags)}")
    
    return enforced
