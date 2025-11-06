# Multi-purpose Jenkins Agent with Node.js, Python, Java, Docker, and ISO tools
FROM jenkins/inbound-agent:latest-jdk21

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    # ISO building tools
    genisoimage \
    xorriso \
    isolinux \
    syslinux-utils \
    squashfs-tools \
    # Additional utilities
    zip \
    unzip \
    jq \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest yarn pnpm && \
    rm -rf /var/lib/apt/lists/*

# Install Python 3.11 and pip
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv python3-dev && \
    pip3 install --no-cache-dir --break-system-packages \
        pipenv \
        poetry \
        virtualenv \
        pytest \
        black \
        flake8 \
        mypy && \
    rm -rf /var/lib/apt/lists/*

# Install Maven (for Java builds)
ARG MAVEN_VERSION=3.9.6
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz -O /tmp/maven.tar.gz && \
    tar -xzf /tmp/maven.tar.gz -C /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven && \
    rm /tmp/maven.tar.gz

# Install Gradle
ARG GRADLE_VERSION=8.5
RUN wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip -O /tmp/gradle.zip && \
    unzip /tmp/gradle.zip -d /opt && \
    ln -s /opt/gradle-${GRADLE_VERSION} /opt/gradle && \
    rm /tmp/gradle.zip

# Set environment variables
ENV MAVEN_HOME=/opt/maven
ENV GRADLE_HOME=/opt/gradle
ENV PATH="${MAVEN_HOME}/bin:${GRADLE_HOME}/bin:${PATH}"

# Create workspace directory
RUN mkdir -p /home/jenkins/workspace && \
    chown -R jenkins:jenkins /home/jenkins

# Switch back to jenkins user
USER jenkins

# Verify installations
RUN node --version && \
    npm --version && \
    python3 --version && \
    pip3 --version && \
    java -version && \
    mvn --version && \
    gradle --version && \
    docker --version

WORKDIR /home/jenkins

# Default entrypoint from parent image
