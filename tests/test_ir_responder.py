"""Lab 11 (SEC-2551): decision logic of lambda/ir-responder/responder.py - no AWS calls."""
import importlib
import os
import sys
import types

import pytest

ROOT = os.path.join(os.path.dirname(__file__), "..", "lambda", "ir-responder")
BUCKET = "cp-lab-data-111111111111"


@pytest.fixture
def responder(monkeypatch):
    boto3 = types.ModuleType("boto3")
    boto3.client = lambda *a, **k: object()          # no SDK, no network
    botocore = types.ModuleType("botocore")
    exc = types.ModuleType("botocore.exceptions")
    exc.ClientError = type("ClientError", (Exception,), {})
    for name, mod in {"boto3": boto3, "botocore": botocore, "botocore.exceptions": exc}.items():
        monkeypatch.setitem(sys.modules, name, mod)
    monkeypatch.setenv("DRY_RUN", "true")
    monkeypatch.setenv("TOPIC_ARN", "arn:aws:sns:us-east-1:111111111111:cp-lab-security-alerts")
    monkeypatch.setenv("DATA_BUCKET", BUCKET)
    monkeypatch.setenv("PROTECTED_ROLES", "cp-admin-role,cp-lab-ir-lambda-role")
    monkeypatch.syspath_prepend(ROOT)
    sys.modules.pop("responder", None)
    mod = importlib.import_module("responder")
    mod.sent = []
    monkeypatch.setattr(mod, "notify", lambda event, result: mod.sent.append(result))
    return mod


def finding(role, severity=8, sample=False):
    return {"source": "aws.guardduty", "detail-type": "GuardDuty Finding", "id": "e1",
            "detail": {"id": "f1", "type": "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS",
                       "severity": severity,
                       "service": {"additionalInfo": {"sample": True} if sample else {}},
                       "resource": {"accessKeyDetails": {"userName": role, "userType": "AssumedRole"}}}}


def s3_call(name, actor_role, bucket=BUCKET):
    return {"source": "aws.s3", "detail-type": "AWS API Call via CloudTrail", "id": "e2",
            "detail": {"eventName": name, "requestParameters": {"bucketName": bucket},
                       "userIdentity": {"arn": f"arn:aws:sts::111111111111:assumed-role/{actor_role}/s"}}}


def test_sample_finding_is_notify_only(responder):
    r = responder.handler(finding("cp-lab11-x", sample=True), None)
    assert r["action"] == "notify-only" and r["reason"] == "sample finding"


def test_admin_role_is_never_contained(responder):
    assert responder.handler(finding("cp-admin-role"), None)["action"] == "notify-only"


def test_low_severity_is_notify_only(responder):
    assert responder.handler(finding("cp-lab11-x", severity=5), None)["reason"] == "severity below 7"


def test_eligible_role_dry_run_would_quarantine(responder):
    r = responder.handler(finding("cp-lab11-ir-test-role"), None)
    assert r["action"] == "would-quarantine-role" and r["dryRun"] is True
    assert len(responder.sent) == 1          # a human is always told


def test_loop_guard_ignores_own_calls(responder):
    r = responder.handler(s3_call("PutBucketPublicAccessBlock", "cp-lab-ir-lambda-role"), None)
    assert r["action"] == "ignored" and responder.sent == []


def test_other_bucket_is_ignored(responder):
    r = responder.handler(s3_call("DeleteBucketPublicAccessBlock", "cp-admin-role", bucket="someone-else"), None)
    assert r["action"] == "ignored"


def test_policy_change_needs_human(responder):
    assert responder.handler(s3_call("PutBucketPolicy", "cp-admin-role"), None)["action"] == "notify-only"


def test_unknown_event_is_ignored_silently(responder):
    r = responder.handler({"source": "x", "detail-type": "y", "detail": {}}, None)
    assert r["action"] == "ignored" and responder.sent == []
