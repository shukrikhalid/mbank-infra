#!/usr/bin/env python3
"""
Task 16 — Platform Defaults Validator
Validates that platform defaults meet regulatory minimums for each environment.

Regulatory Requirements:
- BNM: 7-year audit trail, data residency in Malaysia
- PCI DSS v3.2.1: encryption, MFA, access controls for payment data
- PDPA: personal data protection, encryption, access logs

Usage:
    python platform/schema/test_defaults.py [--verbose]

Exit codes:
    0 = all defaults pass validation
    1 = regulatory minimums not met
"""
import sys
import pathlib
import yaml

DEFAULTS_DIR = pathlib.Path(__file__).parent.parent / "defaults"


class ComplianceValidator:
    """Validates platform defaults against regulatory requirements."""

    def __init__(self, verbose=False):
        self.verbose = verbose
        self.errors = []
        self.warnings = []

    def log(self, msg, level="INFO"):
        """Log messages with optional verbosity control."""
        if self.verbose or level in ["ERROR", "WARNING"]:
            print(f"[{level}] {msg}")

    def error(self, msg):
        """Record an error."""
        self.errors.append(msg)
        self.log(msg, "ERROR")

    def warn(self, msg):
        """Record a warning."""
        self.warnings.append(msg)
        self.log(msg, "WARNING")

    def validate_prod(self, defaults):
        """Validate production defaults against strict regulatory requirements."""
        self.log("Validating prod.yaml...")

        # Encryption: always mandatory
        assert defaults.get("encryption", {}).get("at_rest") is True, \
            "encryption.at_rest must be True in prod"
        assert defaults.get("encryption", {}).get("in_transit") is True, \
            "encryption.in_transit must be True in prod"
        self.log("✓ Encryption requirements met")

        # Network: multi-AZ required for prod
        assert defaults.get("network", {}).get("multi_az") is True, \
            "network.multi_az must be True in prod (HA requirement)"
        self.log("✓ High availability requirements met")

        # Logging: 7-year audit retention (BNM requirement)
        audit_retention = defaults.get("logging", {}).get("audit_log_retention_days", 0)
        assert audit_retention >= 2555, \
            f"Audit log retention must be >= 2555 days (7 years for BNM), got {audit_retention}"
        self.log(f"✓ Audit log retention: {audit_retention} days (>= 2555)")

        app_retention = defaults.get("logging", {}).get("app_log_retention_days", 0)
        assert app_retention >= 90, \
            f"App log retention must be >= 90 days, got {app_retention}"
        self.log(f"✓ App log retention: {app_retention} days")

        # CloudTrail: mandatory for audit
        assert defaults.get("logging", {}).get("cloudtrail") == "enabled", \
            "logging.cloudtrail must be enabled in prod"
        self.log("✓ CloudTrail enabled")

        # VPC Flow Logs: mandatory for network monitoring
        assert defaults.get("logging", {}).get("vpc_flow_logs") == "enabled", \
            "logging.vpc_flow_logs must be enabled in prod"
        self.log("✓ VPC Flow Logs enabled")

        # Backup: 35-day minimum for BNM compliance
        backup_enabled = defaults.get("backup", {}).get("enabled", False)
        assert backup_enabled is True, "backup.enabled must be True in prod"
        backup_days = defaults.get("backup", {}).get("retention_days", 0)
        assert backup_days >= 35, \
            f"Backup retention must be >= 35 days, got {backup_days}"
        self.log(f"✓ Backup: {backup_days} days (>= 35)")

        # Cross-region replication for disaster recovery
        assert defaults.get("backup", {}).get("cross_region_copy") is True, \
            "backup.cross_region_copy must be True in prod"
        self.log("✓ Cross-region backup replication enabled")

        # Vault lock for immutability
        assert defaults.get("backup", {}).get("vault_lock") is True, \
            "backup.vault_lock must be True in prod"
        self.log("✓ Backup vault lock enabled (immutable)")

        # Database: deletion protection and multi-AZ in prod
        db_config = defaults.get("databases", {})
        assert db_config.get("deletion_protection") is True, \
            "databases.deletion_protection must be True in prod"
        assert db_config.get("multi_az") is True, \
            "databases.multi_az must be True in prod"
        assert db_config.get("backup_retention_days", 0) >= 35, \
            "databases.backup_retention_days must be >= 35"
        assert db_config.get("pitr_enabled") is True, \
            "databases.pitr_enabled must be True (point-in-time recovery)"
        self.log("✓ Database compliance requirements met")

        # Compute: minimum 2 instances for HA
        compute_config = defaults.get("compute", {})
        assert compute_config.get("min_instances", 0) >= 2, \
            "compute.min_instances must be >= 2 for HA"
        self.log("✓ Compute HA requirements met (min 2 instances)")

        # Monitoring: alarms must be configured
        monitoring = defaults.get("monitoring", {})
        assert monitoring.get("enable_dashboard") is True, \
            "monitoring.enable_dashboard must be True in prod"
        self.log("✓ Monitoring dashboards enabled")

        # Compliance: GuardDuty, Security Hub, Config enabled
        compliance = defaults.get("compliance", {})
        assert compliance.get("guardduty") == "enabled", \
            "compliance.guardduty must be enabled"
        assert compliance.get("security_hub") == "enabled", \
            "compliance.security_hub must be enabled"
        assert compliance.get("config_rules") == "enabled", \
            "compliance.config_rules must be enabled"
        self.log("✓ Threat detection and compliance monitoring enabled")

        # Security: IMDSv2 and MFA enforcement
        assert compliance.get("imdsv2_required") is True, \
            "compliance.imdsv2_required must be True"
        assert compliance.get("mfa_enforcement") is True, \
            "compliance.mfa_enforcement must be True"
        assert compliance.get("block_public_access") is True, \
            "compliance.block_public_access must be True"
        self.log("✓ Security controls enabled (IMDSv2, MFA, public access block)")

    def validate_staging(self, defaults):
        """Validate staging defaults — relax operationally, keep security."""
        self.log("Validating staging.yaml...")

        # Encryption: still mandatory
        assert defaults.get("encryption", {}).get("at_rest") is True, \
            "encryption.at_rest must be True"
        assert defaults.get("encryption", {}).get("in_transit") is True, \
            "encryption.in_transit must be True"
        self.log("✓ Encryption requirements met")

        # Logging: reduced but still significant
        audit_retention = defaults.get("logging", {}).get("audit_log_retention_days", 0)
        assert audit_retention >= 365, \
            f"Audit log retention must be >= 365 days (1 year), got {audit_retention}"
        self.log(f"✓ Audit log retention: {audit_retention} days")

        # Backup: reduced but still enabled
        backup_enabled = defaults.get("backup", {}).get("enabled", False)
        assert backup_enabled is True, "backup.enabled must be True in staging"
        backup_days = defaults.get("backup", {}).get("retention_days", 0)
        assert backup_days >= 7, \
            f"Backup retention must be >= 7 days, got {backup_days}"
        self.log(f"✓ Backup: {backup_days} days (>= 7)")

        # PITR: keep for disaster recovery testing
        assert defaults.get("databases", {}).get("pitr_enabled") is True, \
            "databases.pitr_enabled must be True (test DR)"
        self.log("✓ PITR enabled for DR testing")

        # Public access block: maintain baseline security
        assert defaults.get("compliance", {}).get("block_public_access") is True, \
            "compliance.block_public_access must be True"
        self.log("✓ S3 public access block enabled")

    def validate_dev(self, defaults):
        """Validate dev defaults — minimal cost, baseline security only."""
        self.log("Validating dev.yaml...")

        # Encryption: baseline minimum
        assert defaults.get("encryption", {}).get("at_rest") is True, \
            "encryption.at_rest must be True (always)"
        assert defaults.get("encryption", {}).get("in_transit") is True, \
            "encryption.in_transit must be True (always)"
        self.log("✓ Encryption baseline met")

        # Public access block: maintain security
        assert defaults.get("compliance", {}).get("block_public_access") is True, \
            "compliance.block_public_access must be True (security baseline)"
        self.log("✓ S3 public access block enabled (security baseline)")

        # These should be disabled in dev for cost saving
        if defaults.get("backup", {}).get("enabled") is True:
            self.warn("Backups enabled in dev (unnecessary cost)")

        if defaults.get("compliance", {}).get("guardduty") == "enabled":
            self.warn("GuardDuty enabled in dev (unnecessary cost)")

    def validate_all(self):
        """Validate all environment defaults."""
        self.log("Starting compliance validation...\n")

        try:
            # Load all defaults
            prod = self._load_yaml(DEFAULTS_DIR / "prod.yaml")
            staging = self._load_yaml(DEFAULTS_DIR / "staging.yaml")
            dev = self._load_yaml(DEFAULTS_DIR / "dev.yaml")

            # Validate each environment
            self.validate_prod(prod)
            print()
            self.validate_staging(staging)
            print()
            self.validate_dev(dev)
            print()

            # Summary
            if self.errors:
                print(f"❌ Validation FAILED: {len(self.errors)} error(s)")
                return False
            else:
                print(f"✅ All validation checks passed")
                if self.warnings:
                    print(f"   ({len(self.warnings)} warning(s) — see above)")
                return True

        except AssertionError as e:
            self.error(str(e))
            return False
        except Exception as e:
            self.error(f"Unexpected error: {e}")
            return False

    @staticmethod
    def _load_yaml(path):
        """Load YAML file."""
        if not path.exists():
            raise FileNotFoundError(f"Defaults file not found: {path}")
        with open(path) as f:
            return yaml.safe_load(f) or {}


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Validate platform defaults against regulatory requirements"
    )
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Enable verbose output")

    args = parser.parse_args()

    validator = ComplianceValidator(verbose=args.verbose)
    success = validator.validate_all()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
