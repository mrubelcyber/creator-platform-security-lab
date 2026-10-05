"""cp-lab-ir-responder - Lab 11 (SEC-2551).
Contain only what is explicitly eligible; notify a human about everything else."""
import datetime, json, logging, os
import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)
sns, iam, s3 = boto3.client("sns"), boto3.client("iam"), boto3.client("s3")

DRY_RUN = os.environ.get("DRY_RUN", "true").lower() != "false"      # anything but "false" = dry run
TOPIC_ARN = os.environ["TOPIC_ARN"]
DATA_BUCKET = os.environ["DATA_BUCKET"]
ROLE_PREFIX = os.environ.get("ROLE_PREFIX", "cp-lab11-")
PROTECTED = {r.strip() for r in os.environ.get("PROTECTED_ROLES", "").split(",") if r.strip()}
SELF_ROLE = os.environ.get("SELF_ROLE", "cp-lab-ir-lambda-role")
QUARANTINE_POLICY = "cp-lab-ir-quarantine"
BPA_EVENTS = {"PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock",
              "PutPublicAccessBlock", "DeletePublicAccessBlock"}
REVIEW_EVENTS = {"PutBucketPolicy", "DeleteBucketPolicy", "PutBucketAcl"}
FULL_BPA = {"BlockPublicAcls": True, "IgnorePublicAcls": True,
            "BlockPublicPolicy": True, "RestrictPublicBuckets": True}


def handler(event, context):
    src, dtype = event.get("source"), event.get("detail-type")
    log.info(json.dumps({"msg": "received", "id": event.get("id"), "source": src, "detailType": dtype}))
    detail = event.get("detail") or {}
    if dtype == "GuardDuty Finding" and src in ("aws.guardduty", "cp-lab.ir-test"):
        result = handle_finding(detail)
    elif dtype == "AWS API Call via CloudTrail" and src == "aws.s3":
        result = handle_s3_call(detail)
    else:
        result = {"action": "ignored", "reason": f"unhandled {src} / {dtype}"}
    result["dryRun"] = DRY_RUN
    log.info(json.dumps({"msg": "result", **result}, default=str))
    if result["action"] != "ignored":
        notify(event, result)
    return result


def handle_finding(d):
    info = (d.get("service") or {}).get("additionalInfo") or {}
    base = {"findingId": d.get("id"), "findingType": d.get("type", ""),
            "severity": float(d.get("severity", 0))}
    if info.get("sample") in (True, "true"):
        return {**base, "action": "notify-only", "reason": "sample finding"}
    if base["findingType"].startswith("Policy:S3/BucketBlockPublicAccessDisabled"):
        buckets = [b.get("name") for b in (d.get("resource") or {}).get("s3BucketDetails") or []]
        if DATA_BUCKET in buckets:
            return {**base, **restore_bpa()}
        return {**base, "action": "notify-only", "reason": "bucket not managed by this responder"}
    akd = (d.get("resource") or {}).get("accessKeyDetails") or {}
    role, utype = akd.get("userName", ""), akd.get("userType")
    base.update(principal=role, userType=utype)
    if base["severity"] < 7:
        return {**base, "action": "notify-only", "reason": "severity below 7"}
    if utype != "AssumedRole":
        return {**base, "action": "notify-only", "reason": "principal is not an IAM role"}
    if role in PROTECTED or not role.startswith(ROLE_PREFIX):
        return {**base, "action": "notify-only", "reason": "role not eligible for auto-containment"}
    return {**base, **quarantine_role(role, d.get("id"))}


def handle_s3_call(d):
    name = d.get("eventName")
    bucket = (d.get("requestParameters") or {}).get("bucketName")
    actor = (d.get("userIdentity") or {}).get("arn", "")
    base = {"eventName": name, "bucket": bucket, "actor": actor}
    if f":assumed-role/{SELF_ROLE}/" in actor:
        return {**base, "action": "ignored", "reason": "own remediation call (loop guard)"}
    if bucket != DATA_BUCKET:
        return {**base, "action": "ignored", "reason": "not the data bucket"}
    if d.get("errorCode"):
        return {**base, "action": "notify-only", "reason": f"call failed ({d['errorCode']}), nothing changed"}
    if name in BPA_EVENTS:
        return {**base, **restore_bpa()}
    if name in REVIEW_EVENTS:
        return {**base, "action": "notify-only", "reason": "policy/ACL change needs human review"}
    return {**base, "action": "ignored", "reason": "event not watched"}


def restore_bpa():
    try:
        current = s3.get_public_access_block(Bucket=DATA_BUCKET)["PublicAccessBlockConfiguration"]
    except ClientError as e:
        if e.response["Error"]["Code"] != "NoSuchPublicAccessBlockConfiguration":
            raise
        current = {}
    if all(current.get(k) for k in FULL_BPA):
        return {"action": "no-change", "reason": "bucket BPA already fully on", "bpaBefore": current}
    if DRY_RUN:
        return {"action": "would-restore-bpa", "bpaBefore": current}
    s3.put_public_access_block(Bucket=DATA_BUCKET, PublicAccessBlockConfiguration=FULL_BPA)
    return {"action": "restored-bpa", "bpaBefore": current}


def quarantine_role(role, finding_id):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if DRY_RUN:
        return {"action": "would-quarantine-role", "role": role}
    policy = {"Version": "2012-10-17", "Statement": [{
        "Sid": "IrQuarantineDenyAll", "Effect": "Deny", "Action": "*", "Resource": "*"}]}
    iam.put_role_policy(RoleName=role, PolicyName=QUARANTINE_POLICY, PolicyDocument=json.dumps(policy))
    iam.tag_role(RoleName=role, Tags=[
        {"Key": "ir-quarantined", "Value": "true"},
        {"Key": "ir-quarantined-at", "Value": now},
        {"Key": "ir-finding-id", "Value": str(finding_id)[:256]}])
    return {"action": "quarantined-role", "role": role, "policy": QUARANTINE_POLICY, "at": now}


def notify(event, result):
    tag = "[DRY-RUN] " if DRY_RUN else ""
    what = result.get("findingType") or result.get("eventName") or "event"
    subject = f"[CP-IR] {tag}{result['action']} - {what}"[:100]
    body = {"result": result, "eventId": event.get("id"), "eventTime": event.get("time"),
            "account": event.get("account"), "region": event.get("region")}
    sns.publish(TopicArn=TOPIC_ARN, Subject=subject, Message=json.dumps(body, indent=2, default=str))
