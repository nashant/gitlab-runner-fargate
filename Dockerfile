FROM gitlab/gitlab-runner:alpine-v13.5.0

ENV URL="" \
    TOKEN="" \
    RUNNER_TOKEN="" \
    NAME="" \
    TAGS="" \
    CLUSTER="" \
    REGION="" \
    SUBNET="" \
    SECURITYGROUP="" \
    TASK="" \
    LOG_LEVEL="warn"

RUN apk add --no-cache python3 py3-pip jq bash curl gettext && \
    pip install awscli && \
    aws --version && \
    mkdir -p /opt/gitlab-runner/fargate && \
    mkdir /opt/gitlab-runner/metadata && \
    mkdir /opt/gitlab-runner/builds && \
    mkdir /opt/gitlab-runner/cache && \
    wget -O /opt/gitlab-runner/fargate/fargate https://gitlab-runner-custom-fargate-downloads.s3.amazonaws.com/latest/fargate-linux-amd64 && \
    chmod 0777 /opt/gitlab-runner/fargate/fargate

ADD config.toml /opt/gitlab-runner/config.toml
ADD fargate-config.toml /opt/gitlab-runner/fargate/config.toml
ADD run.sh /run.sh

ENTRYPOINT ["/run.sh"]
CMD ["run", "--user=root", "--working-directory=/root", "--config=/etc/gitlab-runner/config.toml"]
