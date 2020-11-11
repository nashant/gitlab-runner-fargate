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

stderr "Setting up /etc/gitlab-runner/config.toml"
cat /etc/gitlab-runner/config.toml | envsubst > /etc/gitlab-runner/config.toml

stderr "Setting up /etc/gitlab-runner/fargate/config.toml"
cat /etc/gitlab-runner/fargate/config.toml | envsubst > /etc/gitlab-runner/fargate/config.toml

stderr "Setting private key"
echo "$PRIVATE_KEY" > /etc/gitlab-runner/fargate/id_rsa

stderr "Setting up /etc/gitlab-runner/fargate/fargate"
mkdir /etc/gitlab-runner/{metadata,builds,cache}
chown -R gitlab-runner /etc/gitlab-runner
chmod 0777 /etc/gitlab-runner/fargate/fargate

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
  curl --request POST "$URL/api/v4/runners/verify" --form "token=$RUNNER_TOKEN" -s
}

push_token() {
  stderr "Pushing token to SSM"
  aws ssm put-parameter --region "$REGION" --name "$RUNNER_TOKEN_SSM_PARAMETER" --value "$RUNNER_TOKEN" --type SecureString --overwrite
}

let VALIDATE_COUNT=0
while [[ "$(validate_runner_token)" != "200" ]]; do
  [ $VALIDATE_COUNT -eq 10 ] && error "Unable to register runner"
  [[ "$RUNNER_TOKEN" == "REPLACE_ME" ]] || stderr "Token invalid"
  register_runner
  sleep 10
  let VALIDATE_COUNT++
done

echo "Starting runner"
/usr/bin/dumb-init /entrypoint "$@"