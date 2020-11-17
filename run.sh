#!/bin/bash

stderr() {
  >&2 echo "$*"
}

error() {
  # shellcheck disable=SC2039
  stderr "Error: $1"
  exit 1
}

VARS="PRIVATE_KEY URL REGISTRATION_TOKEN RUNNER_TOKEN RUNNER_TOKEN_SSM_PARAMETER NAME TAGS CLUSTER REGION SUBNET SECURITYGROUP TASK"

verify_var() {
  VAR="$1"
  [ -n "${!VAR}" ] || error "$VAR is a mandatory env var"
}

for VAR in $VARS; do
  verify_var "$VAR"
done

until curl "$URL" -s -o /dev/null; do
  stderr "Trying to curl $URL"
  sleep 5
done

stderr "Waiting for $URL to become ready"
let CHECK_COUNT=0
while [[ "$STATUS" != "ok" ]]; do
  if [ "$CHECK_COUNT" -eq 10 ]; then
    stderr "Unable to get readiness of $URL"
    exit 1
  fi
  STATUS=$(curl -s "$URL/-/readiness" | jq -r '.master_check[0].status')
  [[ "$STATUS" == "ok" ]] && continue
  stderr "Status is $STATUS. Waiting 30s"
  sleep 30
  let CHECK_COUNT++
done

register_runner() {
  stderr "Registering runner"
  RUNNER_TOKEN=$(curl --request POST "$URL/api/v4/runners" --form "token=$REGISTRATION_TOKEN" --form "description=$NAME" --form "tag_list=$TAGS" -s | jq -r '.token')
  push_token
}

validate_runner_token() {
  stderr "Validating runner token"
  curl --request POST "$URL/api/v4/runners/verify" --form "token=$RUNNER_TOKEN" -s | jq -r .
}

push_token() {
  stderr "Pushing token $RUNNER_TOKEN to SSM"
  aws ssm put-parameter --region "$REGION" --name "$RUNNER_TOKEN_SSM_PARAMETER" --value "$RUNNER_TOKEN" --type SecureString --overwrite
}

let VALIDATE_COUNT=0
while true; do
  [ $VALIDATE_COUNT -eq 10 ] && error "Unable to register runner"
  VALIDATION=$(validate_runner_token)
  [[ "$VALIDATION" == "200" ]] && break
  [[ "$RUNNER_TOKEN" == "REPLACE_ME" ]] || stderr "Token invalid: $VALIDATION"
  register_runner
  sleep 10
  let VALIDATE_COUNT++
done

cp -r /opt/gitlab-runner/* /etc/gitlab-runner/

stderr "Setting up /etc/gitlab-runner/config.toml"
envsubst < /opt/gitlab-runner/config.toml > /etc/gitlab-runner/config.toml

stderr "Setting up /etc/gitlab-runner/fargate/config.toml"
envsubst < /opt/gitlab-runner/fargate/config.toml > /etc/gitlab-runner/fargate/config.toml

stderr "Setting private key"
echo "$PRIVATE_KEY" > /etc/gitlab-runner/fargate/id_rsa

stderr "Setting debug public key"
[ -d /root/.ssh ] || mkdir /root/.ssh
echo "$DEBUG_PUBLIC_KEY" > /root/.ssh/authorized_keys

stderr "Setting up /etc/gitlab-runner/fargate/fargate"
chown -R gitlab-runner /etc/gitlab-runner

echo "Starting runner"
/usr/bin/dumb-init /entrypoint "$@"
