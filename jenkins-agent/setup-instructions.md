# Jenkins Docker Agent Setup - Manual Configuration

## Overview
A Docker agent image has been built with the following tools:
- **Node.js**: v20.19.5 with npm, yarn, pnpm
- **Python**: 3.13.5 with pip, pipenv, poetry, pytest, black, flake8, mypy
- **Java**: OpenJDK 21.0.8
- **Maven**: 3.9.6
- **Gradle**: 8.5
- **Docker**: 28.5.1 (for building Docker images)
- **ISO Tools**: genisoimage, xorriso, squashfs-tools, isolinux, syslinux-utils

Image name: `jenkins-agent:multipurpose`

## Manual Configuration Steps

### Option 1: Quick Setup via Script Console (Recommended)

1. Go to https://jenkins.core.mohjave.com/script
2. Paste the following script and click "Run":

```groovy
import jenkins.model.*
import com.nirima.jenkins.plugins.docker.*
import com.nirima.jenkins.plugins.docker.launcher.*
import io.jenkins.docker.connector.*
import com.nirima.jenkins.plugins.docker.strategy.*
import hudson.slaves.*

def jenkins = Jenkins.get()

// Remove existing docker cloud if any
jenkins.clouds.removeIf { it.name == "docker" }

// Create new Docker cloud
def dockerCloud = new DockerCloud(
    "docker",  // name
    [new DockerTemplate(
        "jenkins-agent:multipurpose",  // image
        new DockerComputerJNLPConnector(),  // connector
        "docker docker-agent multipurpose",  // labels
        "/home/jenkins",  // remote FS root
        "10"  // instance cap
    )],
    null,  // credentials
    "unix:///var/run/docker.sock"  // docker host
)

// Configure the template
def template = dockerCloud.templates[0]
template.with {
    remoteFs = "/home/jenkins"
    mode = Node.Mode.EXCLUSIVE

    dockerTemplateBase.with {
        volumesString = "/var/run/docker.sock:/var/run/docker.sock"
        memoryLimit = 4096
        tty = true
    }

    retentionStrategy = new DockerOnceRetentionStrategy(10)
    pullStrategy = DockerImagePullStrategy.PULL_LATEST
    pullTimeout = 300
    removeVolumes = true
}

jenkins.clouds.add(dockerCloud)
jenkins.save()

println "✓ Docker cloud configured successfully!"
println "  - Image: jenkins-agent:multipurpose"
println "  - Labels: docker, docker-agent, multipurpose"
println "  - Docker host: unix:///var/run/docker.sock"
```

### Option 2: Manual UI Configuration

1. Go to https://jenkins.core.mohjave.com/manage/cloud/
2. Click "+ New cloud"
3. Enter name: `docker`
4. Select "Docker" as cloud type
5. Click "Create"

**Docker Host Configuration:**
- Docker Host URI: `unix:///var/run/docker.sock`
- Click "Test Connection" (should show success)
- Enable: ☑ Enabled

**Docker Agent templates:**
Click "Add Docker Template":
- Labels: `docker docker-agent multipurpose`
- Enabled: ☑
- Docker Image: `jenkins-agent:multipurpose`
- Remote File System Root: `/home/jenkins`
- Usage: "Only build jobs with label expressions matching this node"

**Container settings:**
- Volumes: `/var/run/docker.sock:/var/run/docker.sock` (for Docker-in-Docker)
- Memory Limit (MB): `4096`
- Enable TTY: ☑

**Pull Strategy:**
- Pull strategy: "Pull once and update latest"
- Pull timeout: `300`

**Connect method:**
- Select "Connect with JNLP"

**Remove Container Settings:**
- Remove volumes: ☑

Click "Save"

## Testing the Setup

### Test Pipeline 1: Basic Multi-Tool Test

Create a new Pipeline job with this script:

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }

    stages {
        stage('Environment Info') {
            steps {
                sh '''
                    echo "=== System Info ==="
                    uname -a

                    echo "\\n=== Node.js ==="
                    node --version
                    npm --version

                    echo "\\n=== Python ==="
                    python3 --version
                    pip3 --version

                    echo "\\n=== Java ==="
                    java -version
                    mvn --version
                    gradle --version

                    echo "\\n=== Docker ==="
                    docker --version

                    echo "\\n=== ISO Tools ==="
                    which genisoimage xorriso mkisofs
                '''
            }
        }

        stage('Test Node.js Build') {
            steps {
                sh '''
                    echo "console.log('Hello from Node.js!');" > test.js
                    node test.js
                '''
            }
        }

        stage('Test Python Build') {
            steps {
                sh '''
                    echo "print('Hello from Python!')" > test.py
                    python3 test.py
                '''
            }
        }

        stage('Test Java Build') {
            steps {
                sh '''
                    echo 'public class Test { public static void main(String[] args) { System.out.println("Hello from Java!"); }}' > Test.java
                    javac Test.java
                    java Test
                '''
            }
        }
    }
}
```

### Test Pipeline 2: GitHub Integration Test

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }

    stages {
        stage('Clone Repository') {
            steps {
                // Replace with your actual GitHub repo
                git 'https://github.com/your-username/your-repo.git'
            }
        }

        stage('Build') {
            steps {
                // Add your build commands here
                sh 'echo "Building project..."'
            }
        }
    }
}
```

## Troubleshooting

### Agent not starting?
- Check Jenkins logs: https://jenkins.core.mohjave.com/log/all
- Verify docker group membership: `groups jenkins`
- Test Docker connection: `sudo -u jenkins docker ps`

### "Permission denied" errors with Docker?
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Need to rebuild the agent image?
```bash
cd /home/parijat/workspace/home-lab/jenkins-agent
sudo docker build -t jenkins-agent:multipurpose .
```

### View available images:
```bash
sudo docker images | grep jenkins-agent
```

## Next Steps

1. Configure GitHub credentials in Jenkins
2. Set up webhooks in your GitHub repos
3. Create pipeline jobs for your projects
4. Enjoy automated builds!
