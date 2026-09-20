#!/usr/bin/env python3
"""
Task 12 — Schema Validator
Validates one or more infra.yaml files against the JSON Schema.

Usage:
    python platform/schema/validate.py applications/*/infra.yaml [--strict]

Features:
- Support for multiple files (glob patterns)
- Colored output (green ✓ / red ✗)
- Exit code 0 only if ALL files pass
- --strict flag to check recommended fields
"""
import sys
import json
import pathlib
import yaml
import jsonschema
import glob
from typing import List, Tuple


SCHEMA_PATH = pathlib.Path(__file__).parent / "infra-schema.json"

# ANSI color codes
GREEN = "\033[92m"
RED = "\033[91m"
RESET = "\033[0m"


def validate_file(file_path: str, schema: dict, strict: bool = False) -> Tuple[bool, str]:
    """
    Validate a single infra.yaml file.
    Returns (is_valid, message)
    """
    try:
        with open(file_path) as f:
            instance = yaml.safe_load(f)
        
        if instance is None:
            return False, f"File is empty"
        
        # Validate against schema
        jsonschema.validate(instance, schema)
        
        # Strict mode: check recommended fields
        if strict:
            recommended_fields = ["domain", "features", "monitoring", "secrets"]
            missing = [field for field in recommended_fields if field not in instance]
            if missing:
                return True, f"Valid (missing recommended: {', '.join(missing)})"
        
        return True, "Valid"
    
    except json.JSONDecodeError as e:
        return False, f"JSON error: {e}"
    except yaml.YAMLError as e:
        return False, f"YAML error: {e}"
    except jsonschema.ValidationError as e:
        return False, f"Schema validation: {e.message}"
    except FileNotFoundError:
        return False, f"File not found"
    except Exception as e:
        return False, f"Error: {str(e)}"


def expand_paths(patterns: List[str]) -> List[str]:
    """Expand glob patterns to actual file paths."""
    paths = []
    for pattern in patterns:
        expanded = glob.glob(pattern, recursive=True)
        if expanded:
            paths.extend(expanded)
        else:
            paths.append(pattern)  # Return as-is if no matches
    return sorted(set(paths))  # Remove duplicates and sort


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Validate infra.yaml files against the JSON Schema"
    )
    parser.add_argument(
        "files",
        nargs="+",
        help="Path(s) to infra.yaml files (supports glob patterns)"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Check for recommended (non-required) fields"
    )
    
    args = parser.parse_args()
    
    # Load schema
    try:
        with open(SCHEMA_PATH) as f:
            schema = json.load(f)
    except FileNotFoundError:
        print(f"{RED}✗ Schema file not found: {SCHEMA_PATH}{RESET}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"{RED}✗ Invalid JSON schema: {e}{RESET}", file=sys.stderr)
        sys.exit(1)
    
    # Expand file paths
    file_paths = expand_paths(args.files)
    
    if not file_paths:
        print(f"{RED}✗ No files found matching the pattern{RESET}", file=sys.stderr)
        sys.exit(1)
    
    # Validate each file
    results = []
    for file_path in file_paths:
        is_valid, message = validate_file(file_path, schema, args.strict)
        results.append((is_valid, file_path, message))
        
        status = f"{GREEN}✓{RESET}" if is_valid else f"{RED}✗{RESET}"
        print(f"{status} {file_path}: {message}")
    
    # Summary
    valid_count = sum(1 for is_valid, _, _ in results if is_valid)
    total_count = len(results)
    
    print(f"\n{valid_count}/{total_count} files passed validation")
    
    # Exit code: 0 only if all pass
    sys.exit(0 if valid_count == total_count else 1)


if __name__ == "__main__":
    main()
