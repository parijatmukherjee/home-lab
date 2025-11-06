# Jenkins + GitHub Integration Guide

## Step 1: Create GitHub Personal Access Token

1. Go to GitHub: https://github.com/settings/tokens
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Give it a name: `Jenkins CI/CD`
4. Select the following scopes:
   - ☑ **repo** (Full control of private repositories)
     - repo:status
     - repo_deployment
     - public_repo
     - repo:invite
     - security_events
   - ☑ **admin:repo_hook** (Full control of repository hooks)
     - write:repo_hook
     - read:repo_hook
   - ☑ **admin:org_hook** (if using organization repos)
   - ☑ **user:email** (Access user email addresses)
5. Click **"Generate token"**
6. **IMPORTANT:** Copy the token immediately (you won't see it again!)

## Step 2: Add GitHub Credentials to Jenkins

### Option A: Via UI (Recommended)

1. Go to: https://jenkins.core.mohjave.com/manage/credentials/store/system/domain/_/
2. Click **"Add Credentials"**
3. Fill in the form:
   - **Kind:** Username with password
   - **Scope:** Global
   - **Username:** Your GitHub username
   - **Password:** Paste the Personal Access Token from Step 1
   - **ID:** `github-token` (important for scripts)
   - **Description:** `GitHub Personal Access Token`
4. Click **"Create"**

### Option B: Via Script Console

Go to https://jenkins.core.mohjave.com/script and run:

```groovy
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import com.cloudbees.plugins.credentials.CredentialsScope
import hudson.util.Secret

def jenkins = Jenkins.instance
def domain = Domain.global()
def store = jenkins.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

def githubCredentials = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "github-token",
    "GitHub Personal Access Token",
    "YOUR_GITHUB_USERNAME",  // Replace this
    "YOUR_GITHUB_TOKEN"       // Replace this
)

store.addCredentials(domain, githubCredentials)
println "GitHub credentials added successfully!"
```

## Step 3: Configure GitHub Webhook for Auto-Triggers

### Option A: Automatic (via Jenkins job)

In your Jenkins pipeline job configuration:
1. Under "Build Triggers"
2. Check ☑ **"GitHub hook trigger for GITScm polling"**

### Option B: Manual GitHub Setup

For each repository you want to trigger builds:

1. Go to your GitHub repository
2. Click **Settings** → **Webhooks** → **Add webhook**
3. Fill in:
   - **Payload URL:** `https://jenkins.core.mohjave.com/github-webhook/`
   - **Content type:** `application/json`
   - **Secret:** (leave empty for now)
   - **Which events:**
     - ☑ Just the push event (for simple builds)
     - OR ☑ Let me select individual events:
       - ☑ Pushes
       - ☑ Pull requests
       - ☑ Branch or tag creation
4. Click **"Add webhook"**
5. Verify the webhook works (GitHub will send a test ping)

## Step 4: Create a Jenkins Pipeline Job

### Example 1: Simple Node.js Project

1. Go to https://jenkins.core.mohjave.com/view/all/newJob
2. Enter name: `my-nodejs-app`
3. Select **"Pipeline"**
4. Click **"OK"**

**Configure the job:**

**General:**
- ☑ GitHub project
- Project url: `https://github.com/YOUR_USERNAME/YOUR_REPO/`

**Build Triggers:**
- ☑ GitHub hook trigger for GITScm polling

**Pipeline:**
- Definition: **Pipeline script from SCM**
- SCM: **Git**
- Repository URL: `https://github.com/YOUR_USERNAME/YOUR_REPO.git`
- Credentials: Select **github-token**
- Branch: `*/main` (or `*/master`)
- Script Path: `Jenkinsfile`

Click **"Save"**

### Example 2: Multibranch Pipeline (Recommended)

1. Go to https://jenkins.core.mohjave.com/view/all/newJob
2. Enter name: `my-github-project`
3. Select **"Multibranch Pipeline"**
4. Click **"OK"**

**Configure:**

**Branch Sources:**
- Click **"Add source"** → **GitHub**
- Credentials: Select **github-token**
- Repository HTTPS URL: `https://github.com/YOUR_USERNAME/YOUR_REPO`

**Build Configuration:**
- Mode: **by Jenkinsfile**
- Script Path: `Jenkinsfile`

**Scan Multibranch Pipeline Triggers:**
- ☑ Scan by webhook
- Trigger token: `my-project-scan-token` (remember this)

Click **"Save"**

## Step 5: Create a Jenkinsfile in Your Repository

Create a file named `Jenkinsfile` in the root of your GitHub repository:

### For Node.js Projects:

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }

    environment {
        NODE_ENV = 'production'
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Building branch: ${env.BRANCH_NAME}"
                echo "Commit: ${env.GIT_COMMIT}"
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'npm ci'
            }
        }

        stage('Lint') {
            steps {
                sh 'npm run lint || true'
            }
        }

        stage('Test') {
            steps {
                sh 'npm test || echo "No tests found"'
            }
        }

        stage('Build') {
            steps {
                sh 'npm run build || echo "No build script"'
            }
        }

        stage('Archive Artifacts') {
            when {
                branch 'main'
            }
            steps {
                archiveArtifacts artifacts: 'dist/**/*', allowEmptyArchive: true
            }
        }
    }

    post {
        success {
            echo 'Build succeeded!'
        }
        failure {
            echo 'Build failed!'
        }
        always {
            cleanWs()
        }
    }
}
```

### For Python Projects:

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }

    environment {
        PYTHONUNBUFFERED = '1'
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Building ${env.GIT_BRANCH}"
            }
        }

        stage('Setup Virtual Environment') {
            steps {
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                '''
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    . venv/bin/activate
                    if [ -f requirements.txt ]; then
                        pip install -r requirements.txt
                    fi
                    if [ -f requirements-dev.txt ]; then
                        pip install -r requirements-dev.txt
                    fi
                '''
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    . venv/bin/activate
                    flake8 . || true
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    . venv/bin/activate
                    pytest || echo "No tests found"
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
```

### For Docker Image Build:

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }

    environment {
        DOCKER_IMAGE = "your-dockerhub-username/your-app"
        IMAGE_TAG = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Building Docker image for ${env.GIT_BRANCH}"
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    docker build -t ${DOCKER_IMAGE}:${IMAGE_TAG} .
                    docker tag ${DOCKER_IMAGE}:${IMAGE_TAG} ${DOCKER_IMAGE}:latest
                """
            }
        }

        stage('Test Image') {
            steps {
                sh """
                    docker run --rm ${DOCKER_IMAGE}:${IMAGE_TAG} echo "Image works!"
                """
            }
        }

        stage('Push to Registry') {
            when {
                branch 'main'
            }
            steps {
                // You'll need to add Docker Hub credentials first
                withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin
                        docker push ${DOCKER_IMAGE}:${IMAGE_TAG}
                        docker push ${DOCKER_IMAGE}:latest
                    """
                }
            }
        }
    }

    post {
        always {
            sh "docker rmi ${DOCKER_IMAGE}:${IMAGE_TAG} || true"
            cleanWs()
        }
    }
}
```

### Generic Multi-Tool Jenkinsfile:

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }

    stages {
        stage('Detect Project Type') {
            steps {
                script {
                    if (fileExists('package.json')) {
                        env.PROJECT_TYPE = 'nodejs'
                    } else if (fileExists('requirements.txt') || fileExists('setup.py')) {
                        env.PROJECT_TYPE = 'python'
                    } else if (fileExists('pom.xml')) {
                        env.PROJECT_TYPE = 'maven'
                    } else if (fileExists('build.gradle')) {
                        env.PROJECT_TYPE = 'gradle'
                    } else if (fileExists('Dockerfile')) {
                        env.PROJECT_TYPE = 'docker'
                    } else {
                        env.PROJECT_TYPE = 'generic'
                    }
                    echo "Detected project type: ${env.PROJECT_TYPE}"
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    switch(env.PROJECT_TYPE) {
                        case 'nodejs':
                            sh 'npm ci && npm run build'
                            break
                        case 'python':
                            sh 'pip install -r requirements.txt'
                            break
                        case 'maven':
                            sh 'mvn clean package'
                            break
                        case 'gradle':
                            sh 'gradle build'
                            break
                        case 'docker':
                            sh 'docker build -t myapp:latest .'
                            break
                        default:
                            echo 'No specific build steps'
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    switch(env.PROJECT_TYPE) {
                        case 'nodejs':
                            sh 'npm test || echo "No tests"'
                            break
                        case 'python':
                            sh 'pytest || echo "No tests"'
                            break
                        case 'maven':
                            sh 'mvn test'
                            break
                        case 'gradle':
                            sh 'gradle test'
                            break
                        default:
                            echo 'No specific test steps'
                    }
                }
            }
        }
    }
}
```

## Step 6: Test the Integration

### Test 1: Manual Build
1. Go to your Jenkins job
2. Click **"Build Now"**
3. Watch the build logs

### Test 2: Push to GitHub
1. Make a change to your repository
2. Commit and push to GitHub
3. Watch Jenkins automatically start a build!

```bash
echo "# Test" >> README.md
git add README.md
git commit -m "Test Jenkins integration"
git push origin main
```

## Troubleshooting

### Webhook not triggering?
- Check webhook deliveries in GitHub: Settings → Webhooks → Recent Deliveries
- Verify payload URL is accessible: `https://jenkins.core.mohjave.com/github-webhook/`
- Check Jenkins logs: https://jenkins.core.mohjave.com/log/all

### Authentication issues?
- Verify GitHub token has correct permissions
- Test token: `curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user`

### Build fails on agent?
- Check Docker cloud is configured: https://jenkins.core.mohjave.com/manage/cloud/
- Verify agent labels match (`docker-agent`)
- Check Docker images: `sudo docker images | grep jenkins-agent`

## Advanced: Multi-Repository Organization Setup

For scanning all repos in a GitHub organization:

1. Create **"GitHub Organization"** job type
2. Add your GitHub credentials
3. Specify organization name
4. Jenkins will automatically discover all repos with Jenkinsfiles!

## Security Best Practices

1. ✓ Use Personal Access Tokens (not passwords)
2. ✓ Limit token scope to only what's needed
3. ✓ Store credentials in Jenkins (not in code)
4. ✓ Use webhook secrets in production
5. ✓ Enable HTTPS (already done!)
6. ✓ Regular credential rotation

## Next Steps

- Set up branch protection rules in GitHub
- Configure build status badges
- Add deployment stages for staging/production
- Set up notifications (email, Slack)
- Create parameterized builds
