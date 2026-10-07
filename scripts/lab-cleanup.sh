#!/usr/bin/env bash
# =====================================================================
# scripts/lab-cleanup.sh - tear down Creator Platform Labs 8-12 (SEC-2551, SEC-2552)
#   EXPECTED_ACCOUNT=<12-digit id> bash scripts/lab-cleanup.sh          DRY RUN (default), change nothing
#   EXPECTED_ACCOUNT=<12-digit id> bash scripts/lab-cleanup.sh --apply  delete, after you type "yes"
#   option: --keep-key                      do not schedule the KMS key for deletion
# Safety: account/role/region guards; a resource is deleted only if its NAME (cp-lab...)
# AND its TAGS (Project=creator-platform, Lab in 8-12) match; Labs 0-7 + Lab=baseline never touched;
# safe delete order; idempotent (already gone = OK); final verification with retries.
# Lab 12: Security Hub only if every enabled standard is a lab standard (findings exported first),
#   Config recorder/channel + automation rules by cp-lab name (not taggable), Config SLR by tag.
# =====================================================================
# Intentional: ID-list word splitting (SC2046/SC2086), backticks are JMESPath literals (SC2016),
# functions are called indirectly via run (SC2329).
# shellcheck disable=SC2046,SC2086,SC2016,SC2329
set -uo pipefail

EXPECTED_ACCOUNT="${EXPECTED_ACCOUNT:-}"   # your account ID, passed in - never hard-coded
EXPECTED_ROLE="cp-admin-role"
REGION="us-east-1"
LABS_REGEX='^lab-?0?(8|9)$|^lab-?1[0-2]$'   # lab8 lab-08 lab9 lab-10 lab11 lab-12 ...
PROTECTED_ROLES="cp-admin-role"

usage() { sed -n '3,11p' "$0"; }
APPLY=false; KEEP_KEY=false
for a in "$@"; do
  case "$a" in
    --apply) APPLY=true ;;
    --keep-key) KEEP_KEY=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $a"; usage; exit 2 ;;
  esac
done

export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION" AWS_PAGER=""
MODE=$($APPLY && echo apply || echo dryrun)
LOG="$HOME/lab-cleanup-$(date -u +%Y%m%dT%H%M%SZ)-$MODE.log"
exec > >(tee -a "$LOG") 2>&1

say()   { printf '\n=== %s\n' "$*"; }
names() { "$@" 2>/dev/null | tr '\t' '\n' | grep -v -e '^None$' -e '^$' || true; }
tagpair() {  # any AWS tag JSON shape on stdin -> "Project|Lab"
  jq -r '([.. | arrays | select(length > 0 and (.[0] | type) == "object"
            and ((.[0] | has("Key")) or (.[0] | has("TagKey"))))][0]) as $a
    | (if $a then ($a | map({((.Key // .TagKey)): (.Value // .TagValue)}) | add)
       else ([.. | objects | select(has("Project"))][0] // {}) end)
    | "\(.Project // "")|\(.Lab // "")"' 2>/dev/null || echo "|"
}
ours() {  # ours <type> <name> <tags-json>
  local pl p l; pl=$(tagpair <<<"${3:-}"); p=${pl%%|*}; l=${pl#*|}
  if [[ "$p" == "creator-platform" && "$l" =~ $LABS_REGEX ]]; then
    printf '  DELETE %-12s %-50s Lab=%s\n' "$1" "$2" "$l"; return 0; fi
  if [[ "$p" == "creator-platform" ]]; then
    printf '  KEEP   %-12s %-50s Lab=%s (outside labs 8-12)\n' "$1" "$2" "${l:--}"
  else
    printf '  SKIP   %-12s %-50s name matches, tags do not - check manually\n' "$1" "$2"; fi
  return 1
}
FAILS=0
run() {  # run "<what>" <command...>
  local what=$1 out; shift
  if ! $APPLY; then printf '  [dry-run] %s\n' "$what"; return 0; fi
  if out=$("$@" 2>&1); then printf '  [done]    %s\n' "$what"; return 0; fi
  if grep -qiE 'NotFound|NoSuch|does not exist|not found' <<<"$out"; then
    printf '  [gone]    %s\n' "$what"; return 0; fi
  printf '  [FAILED]  %s\n            %s\n' "$what" "$(tr '\n' ' ' <<<"$out" | cut -c1-300)"
  FAILS=$((FAILS + 1)); return 1
}

# ---------------------------------------------------------------- pre-flight
say "Pre-flight - mode: $MODE - log: $LOG"
command -v jq >/dev/null || { echo "STOP: jq is required"; exit 1; }
[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || { echo "STOP: set EXPECTED_ACCOUNT, e.g. EXPECTED_ACCOUNT=123456789012 bash $0"; exit 1; }
ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || { echo "STOP: no valid AWS credentials"; exit 1; }
ACCT=$(cut -d: -f5 <<<"$ARN")
echo "  identity: $ARN"; echo "  region:   $REGION"
[[ "$ACCT" == "$EXPECTED_ACCOUNT" ]] || { echo "STOP: account $ACCT is not $EXPECTED_ACCOUNT"; exit 1; }
[[ "$ARN" == *":assumed-role/$EXPECTED_ROLE/"* ]] || { echo "STOP: must run as $EXPECTED_ROLE"; exit 1; }

# ---------------------------------------------------------------- discovery
say "Discover - name prefix cp-lab AND tags Project=creator-platform + Lab 8-12"
RULES=(); FUNCS=(); QUEUES=(); DETECTORS=(); ALARMS=(); TRAILS=(); TOPICS=()
BUCKETS=(); LOGGROUPS=(); PARAMS=(); VPCS=(); ROLES=(); KEYS=()
RECORDERS=(); CHANNELS=(); SH_RULES=(); ANALYZERS=(); SLRS=(); SECHUB=false

for r in $(names aws events list-rules --name-prefix cp-lab- --query 'Rules[].Name' --output text); do
  ours rule "$r" "$(aws events list-tags-for-resource --resource-arn "arn:aws:events:$REGION:$ACCT:rule/$r" 2>/dev/null)" && RULES+=("$r"); done
for f in $(names aws lambda list-functions --query "Functions[?starts_with(FunctionName,'cp-lab-')].FunctionName" --output text); do
  ours lambda "$f" "$(aws lambda list-tags --resource "arn:aws:lambda:$REGION:$ACCT:function:$f" 2>/dev/null)" && FUNCS+=("$f"); done
for q in $(names aws sqs list-queues --queue-name-prefix cp-lab- --query 'QueueUrls' --output text); do
  ours sqs "${q##*/}" "$(aws sqs list-queue-tags --queue-url "$q" 2>/dev/null)" && QUEUES+=("$q"); done
for d in $(names aws guardduty list-detectors --query 'DetectorIds' --output text); do
  ours guardduty "$d" "$(aws guardduty get-detector --detector-id "$d" --query Tags --output json 2>/dev/null)" && DETECTORS+=("$d"); done
for a in $(names aws cloudwatch describe-alarms --alarm-name-prefix cp-lab- --query 'MetricAlarms[].AlarmName' --output text); do
  ours alarm "$a" "$(aws cloudwatch list-tags-for-resource --resource-arn "arn:aws:cloudwatch:$REGION:$ACCT:alarm:$a" 2>/dev/null)" && ALARMS+=("$a"); done
for t in $(names aws cloudtrail describe-trails --query "trailList[?starts_with(Name,'cp-lab-')].TrailARN" --output text); do
  ours trail "${t##*/}" "$(aws cloudtrail list-tags --resource-id-list "$t" 2>/dev/null)" && TRAILS+=("$t"); done
for t in $(names aws sns list-topics --query "Topics[?contains(TopicArn,':cp-lab-')].TopicArn" --output text); do
  ours sns "${t##*:}" "$(aws sns list-tags-for-resource --resource-arn "$t" 2>/dev/null)" && TOPICS+=("$t"); done
for b in $(names aws s3api list-buckets --query "Buckets[?starts_with(Name,'cp-lab-')].Name" --output text); do
  ours s3 "$b" "$(aws s3api get-bucket-tagging --bucket "$b" 2>/dev/null)" && BUCKETS+=("$b"); done
for g in $(names aws logs describe-log-groups --log-group-name-prefix /cp-lab/ --query 'logGroups[].logGroupName' --output text); do
  ours logs "$g" "$(aws logs list-tags-for-resource --resource-arn "arn:aws:logs:$REGION:$ACCT:log-group:$g" 2>/dev/null)" && LOGGROUPS+=("$g"); done
for p in $(names aws ssm get-parameters-by-path --path /cp-lab --recursive --query 'Parameters[].Name' --output text); do
  ours ssm "$p" "$(aws ssm list-tags-for-resource --resource-type Parameter --resource-id "$p" 2>/dev/null)" && PARAMS+=("$p"); done
for v in $(names aws ec2 describe-vpcs --filters Name=tag:Project,Values=creator-platform --query 'Vpcs[].VpcId' --output text); do
  tags=$(aws ec2 describe-tags --filters Name=resource-id,Values="$v" 2>/dev/null)
  nm=$(jq -r '[.Tags[] | select(.Key=="Name") | .Value][0] // ""' <<<"$tags")
  if [[ "$nm" != cp-lab* ]]; then printf '  SKIP   %-12s %-50s Name tag is not cp-lab*\n' vpc "$v ($nm)"; continue; fi
  ours vpc "$v ($nm)" "$tags" && VPCS+=("$v"); done
for r in $(names aws iam list-roles --query "Roles[?starts_with(RoleName,'cp-')].RoleName" --output text); do
  if [[ " $PROTECTED_ROLES " == *" $r "* ]]; then printf '  KEEP   %-12s %-50s protected\n' iam-role "$r"; continue; fi
  ours iam-role "$r" "$(aws iam list-role-tags --role-name "$r" 2>/dev/null)" && ROLES+=("$r"); done
for al in cp-lab-data-key cp-lab-cspm-trail-key; do
  k=$(aws kms describe-key --key-id "alias/$al" --query 'KeyMetadata.[KeyId,KeyState]' --output text 2>/dev/null || true)
  [[ -n "$k" ]] || continue
  kid=${k%%$'\t'*}; kst=${k##*$'\t'}
  if [[ "$kst" == "PendingDeletion" ]]; then echo "  INFO   kms key $kid (alias/$al) is already PendingDeletion"
  elif ours kms-key "alias/$al ($kid)" "$(aws kms list-resource-tags --key-id "$kid" 2>/dev/null)"; then KEYS+=("$kid|$al"); fi
done
# Lab 12 CSPM - Config recorder/channel and automation rules are not taggable: cp-lab name = ours
for r in $(names aws configservice describe-configuration-recorders --query "ConfigurationRecorders[?starts_with(name,'cp-lab-')].name" --output text); do
  printf '  DELETE %-12s %-50s not taggable - cp-lab- name\n' config "$r"; RECORDERS+=("$r"); done
for c in $(names aws configservice describe-delivery-channels --query "DeliveryChannels[?starts_with(name,'cp-lab-')].name" --output text); do
  printf '  DELETE %-12s %-50s not taggable - cp-lab- name\n' config "$c"; CHANNELS+=("$c"); done
for x in $(names aws securityhub list-automation-rules --query "AutomationRulesMetadata[?starts_with(RuleName,'cp-lab12-')].join('|',[RuleArn,RuleName])" --output text); do
  printf '  DELETE %-12s %-50s not taggable - cp-lab12- name\n' sh-rule "${x#*|}"; SH_RULES+=("${x%%|*}"); done
if hub=$(aws securityhub describe-hub --query HubArn --output text 2>/dev/null); then
  stds=$(names aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].StandardsArn' --output text)
  other=$(grep -v -e 'aws-foundational-security-best-practices/v/1.0.0$' -e 'cis-aws-foundations-benchmark/v/5.0.0$' <<<"$stds" || true)
  if [[ -z "$other" ]]; then printf '  DELETE %-12s %-50s only the lab standards are enabled\n' securityhub "$hub"; SECHUB=true
  else printf '  KEEP   %-12s %-50s other standards enabled: %s\n' securityhub "$hub" "$(tr '\n' ' ' <<<"$other")"; fi
fi
for a in $(names aws accessanalyzer list-analyzers --query "analyzers[?starts_with(name,'cp-lab-')].name" --output text); do
  ours analyzer "$a" "$(aws accessanalyzer get-analyzer --analyzer-name "$a" --query 'analyzer.tags' --output json 2>/dev/null)" && ANALYZERS+=("$a"); done
if t=$(aws iam list-role-tags --role-name AWSServiceRoleForConfig 2>/dev/null); then
  ours iam-slr AWSServiceRoleForConfig "$t" && SLRS+=("AWSServiceRoleForConfig"); fi

say "Plan: ${#RULES[@]} rules, ${#FUNCS[@]} functions, ${#QUEUES[@]} queues, ${#DETECTORS[@]} detectors, ${#ALARMS[@]} alarms, ${#TRAILS[@]} trails, ${#TOPICS[@]} topics, ${#BUCKETS[@]} buckets, ${#VPCS[@]} VPCs, ${#LOGGROUPS[@]} log groups, ${#ROLES[@]} roles, ${#PARAMS[@]} parameters, ${#KEYS[@]} keys, ${#RECORDERS[@]} Config recorders, ${#CHANNELS[@]} channels, ${#SH_RULES[@]} automation rules, ${#ANALYZERS[@]} analyzers, ${#SLRS[@]} service-linked roles, Security Hub: $($SECHUB && echo disable || echo keep)"
if $APPLY; then
  [[ -t 0 ]] || { echo "STOP: --apply needs an interactive terminal"; exit 1; }
  echo "  This PERMANENTLY deletes everything marked DELETE (KMS key: scheduled, 7-day window)."
  read -r -p '  Type "yes" to continue: ' ANSWER
  [[ "$ANSWER" == "yes" ]] || { echo "  Aborted - nothing deleted."; exit 1; }
fi

# ---------------------------------------------------------------- 1 automation
say "Step 1/10 - stop automation first (the responder must not react to the cleanup)"
for r in "${RULES[@]}"; do
  ids=$(names aws events list-targets-by-rule --rule "$r" --query 'Targets[].Id' --output text)
  [[ -n "$ids" ]] && run "remove targets of rule $r" aws events remove-targets --rule "$r" --ids $ids
  run "delete rule $r" aws events delete-rule --name "$r"; done
for f in "${FUNCS[@]}"; do run "delete function $f" aws lambda delete-function --function-name "$f"; done
for q in "${QUEUES[@]}"; do run "delete queue ${q##*/}" aws sqs delete-queue --queue-url "$q"; done

# ---------------------------------------------------------------- 2 guardduty
say "Step 2/10 - GuardDuty: export all findings, then delete the detector (= disable, ends billing)"
for d in "${DETECTORS[@]}"; do
  fids=$(for s in false true; do names aws guardduty list-findings --detector-id "$d" \
           --finding-criteria "{\"Criterion\":{\"service.archived\":{\"Eq\":[\"$s\"]}}}" --query FindingIds --output text; done)
  n=$(wc -w <<<"$fids"); echo "  detector $d: $n findings (current + archived)"
  if $APPLY && (( n > 0 )); then
    out="$HOME/lab-cleanup-guardduty-findings-$d.json"; : > "$out.part"
    xargs -n 50 <<<"$fids" | while read -r chunk; do
      aws guardduty get-findings --detector-id "$d" --finding-ids $chunk --query Findings --output json >> "$out.part"; done
    if jq -s 'add' "$out.part" > "$out" 2>/dev/null && [[ $(jq length "$out") -eq $n ]]; then
      rm -f "$out.part"; echo "  exported $n findings -> $out"
    else echo "  [FAILED]  findings export - detector kept"; FAILS=$((FAILS + 1)); continue; fi
  fi
  run "delete GuardDuty detector $d" aws guardduty delete-detector --detector-id "$d"; done

# ---------------------------------------------------------------- 3 cspm (Lab 12)
say "Step 3/10 - Lab 12 CSPM: automation rules, export Security Hub findings, disable Security Hub, stop + delete Config"
(( ${#SH_RULES[@]} )) && run "delete ${#SH_RULES[@]} automation rules" aws securityhub batch-delete-automation-rules --automation-rules-arns "${SH_RULES[@]}"
if $SECHUB && $APPLY; then
  out="$HOME/lab-cleanup-securityhub-findings-$(date -u +%Y%m%dT%H%M%SZ).json"
  if aws securityhub get-findings --output json > "$out" 2>/dev/null; then
    echo "  exported $(jq '.Findings | length' "$out") findings -> $out"
  else echo "  [FAILED]  findings export - Security Hub kept"; FAILS=$((FAILS + 1)); SECHUB=false; fi
fi
$SECHUB && run "disable Security Hub (standards, controls and findings go with it - ends check billing)" aws securityhub disable-security-hub
for r in "${RECORDERS[@]}"; do run "stop Config recorder $r" aws configservice stop-configuration-recorder --configuration-recorder-name "$r"; done
for c in "${CHANNELS[@]}"; do run "delete Config delivery channel $c" aws configservice delete-delivery-channel --delivery-channel-name "$c"; done
for r in "${RECORDERS[@]}"; do run "delete Config recorder $r (ends CI billing)" aws configservice delete-configuration-recorder --configuration-recorder-name "$r"; done
for a in "${ANALYZERS[@]}"; do run "delete analyzer $a" aws accessanalyzer delete-analyzer --analyzer-name "$a"; done

# ---------------------------------------------------------------- 4 monitoring
say "Step 4/10 - Lab 10 alarms, trail, topic"
(( ${#ALARMS[@]} )) && run "delete ${#ALARMS[@]} alarms" aws cloudwatch delete-alarms --alarm-names "${ALARMS[@]}"
for t in "${TRAILS[@]}"; do
  run "stop logging ${t##*/}" aws cloudtrail stop-logging --name "$t"
  run "delete trail ${t##*/}" aws cloudtrail delete-trail --name "$t"; done
for t in "${TOPICS[@]}"; do run "delete topic ${t##*:} (+ subscriptions)" aws sns delete-topic --topic-arn "$t"; done

# ---------------------------------------------------------------- 5 s3
say "Step 5/10 - S3: data bucket first, logs bucket last (every version + delete marker)"
empty_bucket() {
  local b=$1 batch n total=0 tmp; tmp=$(mktemp)
  while :; do
    batch=$(aws s3api list-object-versions --bucket "$b" --max-items 500 --output json 2>/dev/null \
      | jq -c '{Objects: (((.Versions // []) + (.DeleteMarkers // [])) | map({Key, VersionId})), Quiet: true}')
    n=$(jq '.Objects | length' <<<"$batch" 2>/dev/null || echo 0)
    (( n == 0 )) && break
    printf '%s' "$batch" > "$tmp"
    aws s3api delete-objects --bucket "$b" --delete "file://$tmp" >/dev/null || { rm -f "$tmp"; return 1; }
    total=$((total + n))
  done
  rm -f "$tmp"; echo "removed $total versions/markers"
}
ORD=(); for b in "${BUCKETS[@]}"; do [[ $b == cp-lab-logs-* ]] || ORD+=("$b"); done
for b in "${BUCKETS[@]}"; do [[ $b == cp-lab-logs-* ]] && ORD+=("$b"); done
for b in "${ORD[@]}"; do
  run "turn off access logging on $b" aws s3api put-bucket-logging --bucket "$b" --bucket-logging-status '{}'
  run "empty $b (all versions + delete markers)" empty_bucket "$b"
  run "delete bucket $b" aws s3api delete-bucket --bucket "$b"; done

# ---------------------------------------------------------------- 6 network
say "Step 6/10 - Lab 8 network: flow log, endpoints, IGW, subnets, route tables, NACLs, SGs, VPC"
for v in "${VPCS[@]}"; do
  enis=$(names aws ec2 describe-network-interfaces --filters Name=vpc-id,Values="$v" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
  if [[ -n "$enis" ]]; then echo "  [BLOCKED] $v still has network interfaces: $enis"; FAILS=$((FAILS + 1)); continue; fi
  for x in $(names aws ec2 describe-flow-logs --filter Name=resource-id,Values="$v" --query 'FlowLogs[].FlowLogId' --output text); do
    run "delete flow log $x" aws ec2 delete-flow-logs --flow-log-ids "$x"; done
  for x in $(names aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$v" --query 'VpcEndpoints[].VpcEndpointId' --output text); do
    run "delete endpoint $x" aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$x"; done
  for x in $(names aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$v" --query 'InternetGateways[].InternetGatewayId' --output text); do
    run "detach $x" aws ec2 detach-internet-gateway --internet-gateway-id "$x" --vpc-id "$v"
    run "delete $x" aws ec2 delete-internet-gateway --internet-gateway-id "$x"; done
  for x in $(names aws ec2 describe-subnets --filters Name=vpc-id,Values="$v" --query 'Subnets[].SubnetId' --output text); do
    run "delete subnet $x" aws ec2 delete-subnet --subnet-id "$x"; done
  for x in $(names aws ec2 describe-route-tables --filters Name=vpc-id,Values="$v" --query 'RouteTables[?!(Associations[?Main])].RouteTableId' --output text); do
    run "delete route table $x" aws ec2 delete-route-table --route-table-id "$x"; done
  for x in $(names aws ec2 describe-network-acls --filters Name=vpc-id,Values="$v" --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text); do
    run "delete network ACL $x" aws ec2 delete-network-acl --network-acl-id "$x"; done
  SGS=$(names aws ec2 describe-security-groups --filters Name=vpc-id,Values="$v" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for x in $SGS; do   # revoke first: SGs that reference each other cannot be deleted
    in=$(names aws ec2 describe-security-group-rules --filters Name=group-id,Values="$x" --query 'SecurityGroupRules[?!IsEgress].SecurityGroupRuleId' --output text)
    eg=$(names aws ec2 describe-security-group-rules --filters Name=group-id,Values="$x" --query 'SecurityGroupRules[?IsEgress].SecurityGroupRuleId' --output text)
    [[ -n "$in" ]] && run "revoke ingress rules of $x" aws ec2 revoke-security-group-ingress --group-id "$x" --security-group-rule-ids $in
    [[ -n "$eg" ]] && run "revoke egress rules of $x" aws ec2 revoke-security-group-egress --group-id "$x" --security-group-rule-ids $eg; done
  for x in $SGS; do run "delete security group $x" aws ec2 delete-security-group --group-id "$x"; done
  run "delete VPC $v (main route table, default NACL/SG go with it)" aws ec2 delete-vpc --vpc-id "$v"; done

# ---------------------------------------------------------------- 7 log groups
say "Step 7/10 - log groups (their metric filters go with them)"
for g in "${LOGGROUPS[@]}"; do run "delete log group $g" aws logs delete-log-group --log-group-name "$g"; done

# ---------------------------------------------------------------- 8 iam
say "Step 8/10 - IAM roles (after everything that uses them is gone)"
delete_role() {
  local r=$1 p
  for p in $(names aws iam list-role-policies --role-name "$r" --query PolicyNames --output text); do
    aws iam delete-role-policy --role-name "$r" --policy-name "$p" || return 1; done
  for p in $(names aws iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$r" --policy-arn "$p" || return 1; done
  for p in $(names aws iam list-instance-profiles-for-role --role-name "$r" --query 'InstanceProfiles[].InstanceProfileName' --output text); do
    aws iam remove-role-from-instance-profile --instance-profile-name "$p" --role-name "$r" || return 1; done
  aws iam delete-role --role-name "$r"
}
for r in "${ROLES[@]}"; do run "delete role $r (policies first)" delete_role "$r"; done
for r in "${SLRS[@]}"; do run "delete service-linked role $r (AWS deletes it asynchronously)" aws iam delete-service-linked-role --role-name "$r"; done

# ---------------------------------------------------------------- 9 ssm / ebs / kms
say "Step 9/10 - SSM parameters, EBS default key, KMS key (last - everything it encrypted is gone)"
for p in "${PARAMS[@]}"; do run "delete parameter $p" aws ssm delete-parameter --name "$p"; done
for ka in "${KEYS[@]}"; do
  KEY=${ka%%|*}; AL=${ka#*|}
  ebs=$(aws ec2 get-ebs-default-kms-key-id --query KmsKeyId --output text 2>/dev/null || true)
  if [[ "$ebs" == *"$KEY"* || "$ebs" == *"$AL"* ]]; then
    run "reset EBS default key to aws/ebs (EBS encryption stays ON)" aws ec2 reset-ebs-default-kms-key-id; fi
  if $KEEP_KEY; then echo "  [kept]    KMS key $KEY (--keep-key)"
  else
    run "delete alias alias/$AL" aws kms delete-alias --alias-name "alias/$AL"
    run "schedule deletion of key $KEY in 7 days (undo: aws kms cancel-key-deletion)" \
      aws kms schedule-key-deletion --key-id "$KEY" --pending-window-in-days 7
  fi
done

# ---------------------------------------------------------------- 10 verify
check() {  # check "<label>" <list command...>  -> PASS if it lists nothing
  local label=$1 x; shift; x=$(names "$@")
  if [[ -n "$x" ]]; then printf '  FAIL  %-26s %s\n' "$label" "$(tr '\n' ' ' <<<"$x")"; return 1; fi
  printf '  PASS  %s\n' "$label"
}
verify() {
  local f=0 r st
  check "EventBridge rules"   aws events list-rules --name-prefix cp-lab- --query 'Rules[].Name' --output text || f=1
  check "Lambda functions"    aws lambda list-functions --query "Functions[?starts_with(FunctionName,'cp-lab-')].FunctionName" --output text || f=1
  check "SQS queues"          aws sqs list-queues --queue-name-prefix cp-lab- --query QueueUrls --output text || f=1
  check "GuardDuty detectors" aws guardduty list-detectors --query DetectorIds --output text || f=1
  check "CloudWatch alarms"   aws cloudwatch describe-alarms --alarm-name-prefix cp-lab- --query 'MetricAlarms[].AlarmName' --output text || f=1
  check "CloudTrail trails"   aws cloudtrail describe-trails --query "trailList[?starts_with(Name,'cp-lab-')].Name" --output text || f=1
  check "SNS topics"          aws sns list-topics --query "Topics[?contains(TopicArn,':cp-lab-')].TopicArn" --output text || f=1
  check "S3 buckets"          aws s3api list-buckets --query "Buckets[?starts_with(Name,'cp-lab-')].Name" --output text || f=1
  check "Log groups /cp-lab/" aws logs describe-log-groups --log-group-name-prefix /cp-lab/ --query 'logGroups[].logGroupName' --output text || f=1
  check "SSM /cp-lab"         aws ssm get-parameters-by-path --path /cp-lab --recursive --query 'Parameters[].Name' --output text || f=1
  check "VPCs (creator-platform)" aws ec2 describe-vpcs --filters Name=tag:Project,Values=creator-platform --query 'Vpcs[].VpcId' --output text || f=1
  for r in "${ROLES[@]}"; do
    if aws iam get-role --role-name "$r" >/dev/null 2>&1; then printf '  FAIL  %-26s %s\n' "IAM role" "$r"; f=1
    else printf '  PASS  IAM role %s deleted\n' "$r"; fi; done
  for ka in "${KEYS[@]}"; do
    $KEEP_KEY && break
    st=$(aws kms describe-key --key-id "${ka%%|*}" --query KeyMetadata.KeyState --output text 2>/dev/null)
    if [[ "$st" == "PendingDeletion" ]]; then printf '  PASS  KMS key %s PendingDeletion\n' "${ka#*|}"
    else printf '  FAIL  KMS key %s state %s\n' "${ka#*|}" "$st"; f=1; fi
  done
  check "Config recorders cp-lab-"   aws configservice describe-configuration-recorders --query "ConfigurationRecorders[?starts_with(name,'cp-lab-')].name" --output text || f=1
  check "Config channels cp-lab-"    aws configservice describe-delivery-channels --query "DeliveryChannels[?starts_with(name,'cp-lab-')].name" --output text || f=1
  check "Automation rules cp-lab12-" aws securityhub list-automation-rules --query "AutomationRulesMetadata[?starts_with(RuleName,'cp-lab12-')].RuleName" --output text || f=1
  if $SECHUB; then
    if aws securityhub describe-hub >/dev/null 2>&1; then printf '  FAIL  Security Hub still enabled\n'; f=1
    else printf '  PASS  Security Hub disabled\n'; fi
  fi
  for a in "${ANALYZERS[@]}"; do
    if aws accessanalyzer get-analyzer --analyzer-name "$a" >/dev/null 2>&1; then printf '  FAIL  analyzer %s\n' "$a"; f=1
    else printf '  PASS  analyzer %s deleted\n' "$a"; fi; done
  return $f
}
if $APPLY; then
  say "Step 10/10 - final verification (retries for eventual consistency)"
  for attempt in 1 2 3; do
    verify && { echo "  ALL CHECKS PASSED"; break; }
    if (( attempt < 3 )); then echo "  ...retry $attempt/2 in 20 s"; sleep 20; else FAILS=$((FAILS + 1)); fi
  done
  echo "  still tagged creator-platform (tagging API can lag for minutes; expect Lab 7 items + pending key):"
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=creator-platform \
    --query 'ResourceTagMappingList[].[ResourceARN, Tags[?Key==`Lab`]|[0].Value]' --output text | sed 's/^/    /'
else
  say "Step 10/10 - verification runs only with --apply"
fi

say "Summary - mode: $MODE - failures: $FAILS - log: $LOG"
$APPLY && echo "  Kept on purpose: account S3 Block Public Access, EBS default encryption, budget, Lab 0-7 IAM (cp-admin-role, OIDC provider, boundaries), GuardDuty + Security Hub service-linked roles, Lab=baseline hardening (password policy, support role, SSM/EBS/VPC block-public settings, security contact, Access Analyzer), default VPC."
$APPLY || echo "  DRY RUN - nothing was changed. Review every DELETE/KEEP/SKIP line, then run with --apply."
exit $(( FAILS > 0 ? 1 : 0 ))
