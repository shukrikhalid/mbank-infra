#!/usr/bin/env python3
"""
Task 13 — Infrastructure Generator
Main pipeline: load infra.yaml → merge defaults → enforce locks → validate → emit Terraform.

Usage:
    python generator.py applications/payment/infra.yaml [prod|staging|dev]

Outputs:
    - applications/payment/terraform.tfvars.json (Terraform variable values)
    - applications/payment/module.tf (Terraform module invocation)
"""
import sys
import json
import yaml
import pathlib
import jsonschema
from merger import merge, deep_merge
from enforcer import enforce


MODULE_MAPPING = {
    "ecs": "ecs-service",
    "ec2": "ec2-autoscaling",
    "eks": "eks-workload",
}

SCHEMA_PATH = pathlib.Path(__file__).parents[2] / "platform" / "schema" / "infra-schema.json"


def flatten_dict(d: dict, parent_key: str = "", sep: str = "_") -> dict:
    """
    Flatten nested dict to single level using snake_case (for Terraform variables).
    E.g., {"compute": {"cpu": 512}} → {"compute_cpu": 512}
    """
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        elif isinstance(v, list) and v and isinstance(v[0], dict):
            # For lists of objects, keep as-is (Terraform handles them)
            items.append((new_key, v))
        else:
            items.append((new_key, v))
    return dict(items)


def generate_module_tf(app_name: str, compute_type: str, output_dir: pathlib.Path) -> None:
    """
    Generate a module.tf file that invokes the appropriate platform module.
    """
    module_name = MODULE_MAPPING.get(compute_type, compute_type)
    module_source = f"../../platform/modules/{module_name}"
    
    # Generate locals block that uses tfvars as input
    module_tf_content = f'''terraform {{
  required_version = "~> 1.0"
  required_providers {{
    aws = {{
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }}
  }}
}}

provider "aws" {{
  region = "ap-southeast-5"
}}

locals {{
  tfvars = jsondecode(file("${{path.module}}/terraform.tfvars.json"))
}}

module "{app_name}" {{
  source = "{module_source}"

  app_name             = local.tfvars.app
  environment          = local.tfvars.environment
  team                 = local.tfvars.team
  cost_centre          = local.tfvars.cost_centre
  data_classification  = local.tfvars.data_classification

  # Compute configuration
  type             = local.tfvars.compute.type
  cpu              = lookup(local.tfvars.compute, "cpu", 512)
  memory           = lookup(local.tfvars.compute, "memory", 1024)
  desired_count    = lookup(local.tfvars.compute, "desired_count", 2)
  container_port   = lookup(local.tfvars.compute, "container_port", 8080)
  health_check_path = lookup(local.tfvars.compute, "health_check_path", "/health")

  # Tags
  tags = local.tfvars.tags
}}

output "module_outputs" {{
  description = "Module outputs"
  value       = module."{app_name}"
}}
'''
    
    output_path = output_dir / "module.tf"
    output_path.write_text(module_tf_content)
    print(f"Generated: {output_path}")


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print(
            "Usage: python generator.py <path/to/infra.yaml> [env]",
            file=sys.stderr,
        )
        print(f"  env: prod (default), staging, dev", file=sys.stderr)
        sys.exit(1)
    
    infra_path = pathlib.Path(sys.argv[1])
    env = sys.argv[2] if len(sys.argv) > 2 else "prod"
    
    if env not in ["prod", "staging", "dev"]:
        print(f"ERROR: Invalid environment '{env}'", file=sys.stderr)
        sys.exit(1)
    
    if not infra_path.exists():
        print(f"ERROR: File not found: {infra_path}", file=sys.stderr)
        sys.exit(1)
    
    # Load infra.yaml
    with open(infra_path) as f:
        infra = yaml.safe_load(f)
    
    if not infra:
        print(f"ERROR: {infra_path} is empty", file=sys.stderr)
        sys.exit(1)
    
    # Step 1: Merge defaults with infra.yaml
    try:
        merged = merge(infra, env)
    except Exception as e:
        print(f"ERROR during merge: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Step 1b: Load and merge environment-specific overrides (env/X.yaml)
    app_dir = infra_path.parent
    env_override_path = app_dir / "env" / f"{env}.yaml"
    if env_override_path.exists():
        try:
            with open(env_override_path) as f:
                env_overrides = yaml.safe_load(f)
            if env_overrides:
                merged = deep_merge(merged, env_overrides)
                print(f"Merged environment config: {env_override_path}")
        except Exception as e:
            print(f"WARNING: Failed to load env override {env_override_path}: {e}", file=sys.stderr)
    else:
        print(f"INFO: No environment config found at {env_override_path}, using defaults only")
    
    # Step 2: Enforce locked fields
    try:
        enforced = enforce(merged, env)
    except Exception as e:
        print(f"ERROR during enforce: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Step 3: Validate against schema
    try:
        with open(SCHEMA_PATH) as f:
            schema = json.load(f)
        jsonschema.validate(enforced, schema)
        print(f"✓ Validation passed: {infra_path}")
    except FileNotFoundError:
        print(f"WARNING: Schema not found at {SCHEMA_PATH}")
    except jsonschema.ValidationError as e:
        print(f"ERROR: Validation failed: {e.message}", file=sys.stderr)
        sys.exit(1)
    
    # Step 4: Flatten and emit terraform.tfvars.json
    output_dir = infra_path.parent
    tfvars_path = output_dir / "terraform.tfvars.json"
    
    # Keep nested structure for terraform (don't fully flatten)
    with open(tfvars_path, "w") as f:
        json.dump(enforced, f, indent=2)
    print(f"Generated: {tfvars_path}")
    
    # Step 5: Generate module.tf
    compute_type = enforced.get("compute", {}).get("type", "ecs")
    try:
        generate_module_tf(enforced.get("app", "app"), compute_type, output_dir)
    except Exception as e:
        print(f"WARNING: Could not generate module.tf: {e}", file=sys.stderr)
    
    print(f"✓ Generation complete for {infra_path}")


if __name__ == "__main__":
    main()
