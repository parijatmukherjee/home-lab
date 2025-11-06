# TeamCity Setup Guide

## ✅ Installation Complete!

TeamCity Community Edition is now installed and running at:
**https://teamcity.core.mohjave.com**

## 🚀 Initial Setup Steps

### Step 1: Complete Initial Setup Wizard

1. **Open TeamCity:** https://teamcity.core.mohjave.com

2. **Accept License Agreement**
   - Click "Continue"
   - Accept the license agreement

3. **Database Setup**
   - Select **"Internal (HSQLDB)"** for simple setup
   - This is perfect for homelab use
   - Click "Proceed"

4. **Create Administrator Account**
   - Username: `admin`
   - Password: (choose a strong password)
   - Email: `parijat_mukherjee@live.com`
   - Click "Create Account"

5. **Initial Configuration**
   - TeamCity will initialize (takes 1-2 minutes)
   - You'll be redirected to the main dashboard

### Step 2: Connect GitHub (SUPER EASY in TeamCity!)

1. **Go to Administration** (top right, click your username → Administration)

2. **Add VCS Root:**
   - Click **"Projects"** in the left menu
   - Click **"Create project"**
   - Select **"From a repository URL"**

3. **Enter GitHub Repository:**
   - **Repository URL:** `https://github.com/mohjave-os/mohjave.git`
   - **Username:** `parijatmukherjee`
   - **Password:** `<your-github-personal-access-token>`
   - Click **"Proceed"**

4. **Auto-detect Project Settings:**
   - TeamCity will scan your repository
   - It will auto-detect build scripts (Maven, Gradle, npm, etc.)
   - Just click **"Proceed"**!

### Step 3: Authorize Build Agent

1. **Go to Agents** (top menu → Agents)
2. You should see **"docker-agent-1"** as Unauthorized
3. Click on the agent
4. Click **"Authorize"**
5. The agent is now ready to build!

### Step 4: Create Your First Build

For mohjave-os project, create a custom build configuration:

1. **In your project** → Click **"Create build configuration"**
2. **Name:** `Build Mohjave`
3. **Build Steps** → **Add build step:**
   - **Runner type:** Command Line
   - **Step name:** `Build ISO`
   - **Script:**
   ```bash
   #!/bin/bash
   make build || ./build.sh || echo "Add your build commands here"
   ```

4. **Triggers** → **Add trigger:**
   - Select **"VCS Trigger"**
   - This will automatically trigger builds on every push!

5. Click **"Save"**

### Step 5: Run Your First Build

1. Click **"Run"** button (top right)
2. Watch the build in real-time!
3. TeamCity will show you:
   - Build log (MUCH cleaner than Jenkins!)
   - Test results
   - Build artifacts
   - Build time

## 🎯 TeamCity vs Jenkins - Why It's Better

### ✅ Easier to Use:
- No plugin hell!
- Auto-detects project types
- Clean, intuitive UI
- Better build logs

### ✅ GitHub Integration:
- Just username + token (no complex OAuth)
- Auto-detects branches and PRs
- Built-in webhook support

### ✅ Better Agent Management:
- Agents auto-connect
- No complex configuration
- Docker support out of the box

### ✅ Free Forever:
- 100 build configurations
- 3 build agents
- Unlimited users
- Perfect for homelab!

## 📊 TeamCity Features You'll Love

### 1. Build Chains
   - Link multiple builds together
   - Example: Build → Test → Deploy

### 2. Artifact Dependencies
   - Automatically pass artifacts between builds
   - No manual scripting needed!

### 3. Test Reporting
   - Beautiful test result UI
   - Automatically detects test failures
   - Tracks test history

### 4. Build History
   - See all builds at a glance
   - Compare builds
   - Easy rollback

### 5. Notifications
   - Email on build failure
   - Slack integration
   - RSS feeds

## 🔐 Security Best Practices

1. **Change Admin Password:**
   - Profile → Change Password

2. **Create Build User:**
   - Administration → Users
   - Create a user for builds (not admin)

3. **Use SSH Keys for GitHub:**
   - Generate SSH key in TeamCity
   - Add to GitHub instead of using PAT

4. **Enable 2FA:**
   - Profile → Two-Factor Authentication

## 🛠️ Common Build Configurations

### For Node.js/JavaScript Projects:

```bash
# Install dependencies
npm ci

# Run tests
npm test

# Build
npm run build

# Package
tar -czf dist.tar.gz dist/
```

### For Python Projects:

```bash
# Create venv
python3 -m venv venv
. venv/bin/activate

# Install
pip install -r requirements.txt

# Test
pytest

# Build
python setup.py sdist
```

### For Docker Builds:

```bash
# Build image
docker build -t myapp:${build.number} .

# Test
docker run --rm myapp:${build.number} test

# Push (if build succeeds)
docker push myapp:${build.number}
```

### For ISO Builds (your mohjave project):

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y genisoimage xorriso squashfs-tools

# Run build script
./build-iso.sh

# Package ISO
mkdir -p artifacts
cp *.iso artifacts/
```

## 📁 Manage Build Artifacts

TeamCity makes artifacts super easy:

1. **In Build Configuration** → **General Settings**
2. **Artifact paths:** `*.iso => mohjave-builds/`
3. TeamCity automatically stores and serves them!

## 🌐 Webhooks (Auto-trigger from GitHub)

TeamCity can create webhooks automatically!

1. **Project Settings** → **Connections**
2. **Add Connection** → **GitHub.com**
3. Enter your GitHub token
4. TeamCity will automatically create webhooks!

OR manually:

- **Payload URL:** `https://teamcity.core.mohjave.com/app/rest/vcs-root-instances/commitHookNotification?locator=vcsRoot:YOUR_VCS_ROOT_ID`
- Get VCS Root ID from: Project Settings → VCS Roots

## 🎨 TeamCity Tips & Tricks

### 1. Build Parameters
   - Use `%build.number%` in scripts
   - Use `%vcsroot.branch%` for branch name
   - Create custom parameters

### 2. Build Matrix
   - Test on multiple platforms
   - Example: Node 18, 20, 22

### 3. Build Status Badge
   - Add to GitHub README:
   ```markdown
   ![Build Status](https://teamcity.core.mohjave.com/app/rest/builds/buildType:YourBuildId/statusIcon.svg)
   ```

### 4. Agent Requirements
   - Require specific agent properties
   - Example: Docker, Node.js version, etc.

### 5. Failure Conditions
   - Fail build on specific text in log
   - Fail if tests take too long
   - Custom failure conditions

## 🆘 Troubleshooting

### Agent Not Connecting? (Permission Denied Errors)

If the agent shows "permission denied" errors or keeps restarting:

**Symptom:** Agent logs show `cp: cannot create regular file '/data/teamcity_agent/conf/...': Permission denied`

**Fix:**
```bash
# Fix agent directory permissions (agent runs as UID 1000)
sudo chown -R 1000:1000 /srv/data/teamcity/agent
sudo docker restart teamcity-agent-1
```

Or use the helper script:
```bash
cd /home/parijat/workspace/home-lab/teamcity
./scripts/fix-agent-permissions.sh
```

### Agent Shows "Incompatible runner: Docker Compose"

If the agent can't run Docker builds:

**Symptom:** Build fails with "Incompatible runner: Docker" or "Docker Compose"

**Cause:** Agent doesn't have access to Docker socket due to GID mismatch

**Fix:** The `docker-compose.yml` should include `group_add` with your host's docker group GID:

```yaml
teamcity-agent:
  # ... other config ...
  group_add:
    - "984"  # Your host docker group GID
```

To find your docker group GID:
```bash
getent group docker | cut -d: -f3
```

**Verify Docker access:**
```bash
# Test if agent can access Docker
sudo docker exec teamcity-agent-1 docker ps

# Test Docker Compose
sudo docker exec teamcity-agent-1 docker compose version
```

### Agent Not Connecting?
```bash
sudo docker logs teamcity-agent-1
sudo docker restart teamcity-agent-1
```

### Need More Agents?
Edit `/home/parijat/workspace/home-lab/teamcity/docker-compose.yml`:
```yaml
teamcity-agent-2:
  image: jetbrains/teamcity-agent:latest
  group_add:
    - "984"  # Same docker group as agent-1
  # ... rest of config similar to agent-1 ...
```

### TeamCity Not Starting?
```bash
sudo docker logs teamcity-server
sudo docker restart teamcity-server
```

### Check Status:
```bash
sudo docker ps | grep teamcity
curl -I https://teamcity.core.mohjave.com
```

### Fresh Installation

To install TeamCity using the automated script:
```bash
sudo /opt/core-setup/scripts/modules.d/module-teamcity.sh
```

This script will:
- Install Docker and Docker Compose
- Create directories with correct permissions
- Configure docker-compose.yml with proper Docker socket access
- Start TeamCity server and agent
- Verify installation

## 📚 Resources

- **Official Docs:** https://www.jetbrains.com/help/teamcity/
- **GitHub Plugin:** https://www.jetbrains.com/help/teamcity/integrating-teamcity-with-vcs-hosting-services.html
- **Docker Guide:** https://www.jetbrains.com/help/teamcity/docker-wrapper.html

## 🎉 You're All Set!

TeamCity is SO much simpler than Jenkins! Enjoy your new CI/CD setup!

**Access TeamCity:** https://teamcity.core.mohjave.com

---

**Need help?** Just ask! TeamCity is way easier than Jenkins - you'll see! 😊
