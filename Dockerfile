FROM concourse/buildroot:base

ADD assets/ /opt/resource/
ADD itest/ /opt/itest/

# Install Cloud Foundry cli
ADD https://cli.run.pivotal.io/stable?release=linux64-binary&version=6.35.2 /tmp/cf-cli.tgz
RUN mkdir -p /usr/local/bin && \
  tar -xzf /tmp/cf-cli.tgz -C /usr/local/bin && \
  cf --version && \
  rm -f /tmp/cf-cli.tgz

# Install cf cli Autopilot plugin
ADD https://github.com/contraband/autopilot/releases/download/0.0.3/autopilot-linux /tmp/autopilot-linux
RUN chmod +x /tmp/autopilot-linux && \
  cf install-plugin /tmp/autopilot-linux -f && \
  rm -f /tmp/autopilot-linux

# Install yaml cli
ADD https://storage.googleapis.com/cf-cli-resource/yaml_linux_amd64 /tmp/yaml_linux_amd64
RUN install /tmp/yaml_linux_amd64 /usr/local/bin/yaml && \
  yaml --help && \
  rm -f /tmp/yaml_linux_amd64

# Install cf mysql plugin feature 
ADD https://github.com/andreasf/cf-mysql-plugin/releases/download/v2.0.0/cf-mysql-plugin-linux-amd64 /tmp/cf-mysql-plugin
RUN chmod +x /tmp/cf-mysql-plugin/cf-mysql-plugin-linux-amd64 && \
  cp /tmp/cf-mysql-plugin/cf-mysql-plugin-linux-amd64 /usr/local/bin
