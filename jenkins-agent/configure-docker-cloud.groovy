import jenkins.model.*
import com.nirima.jenkins.plugins.docker.*
import com.nirima.jenkins.plugins.docker.launcher.*
import io.jenkins.docker.connector.*
import com.nirima.jenkins.plugins.docker.strategy.*

def jenkins = Jenkins.get()

// Docker Cloud configuration
def dockerCloudName = "docker"
def dockerHostUrl = "unix:///var/run/docker.sock"

// Create Docker Cloud
def dockerCloud = new DockerCloud(
    dockerCloudName,
    [new DockerTemplate(
        "jenkins-agent:multipurpose",  // Docker image
        new DockerComputerJNLPConnector(new JNLPLauncher()),
        "docker-agent",  // Label
        "/home/jenkins",  // Remote FS root
        "3"  // Instance capacity
    )],
    null, // server credentials
    dockerHostUrl
)

// Set Docker template properties
def template = dockerCloud.getTemplates()[0]
template.with {
    labelString = "docker docker-agent multipurpose"
    remoteFs = "/home/jenkins"
    instanceCapStr = "10"
    mode = io.jenkins.jenkins.model.Jenkins.ModeSet.EXCLUSIVE

    // Docker container configuration
    dockerTemplateBase.with {
        image = "jenkins-agent:multipurpose"
        dnsString = ""
        network = ""
        dockerCommand = ""
        volumesString = "/var/run/docker.sock:/var/run/docker.sock"  // Mount Docker socket for Docker-in-Docker
        volumesFromString = ""
        environmentsString = ""
        hostname = ""
        memoryLimit = 4096
        memorySwap = -1
        cpuShares = null
        bindPorts = ""
        bindAllPorts = false
        privileged = false
        tty = true
        macAddress = ""
        extraHostsString = ""
    }

    // Retention strategy
    retentionStrategy = new DockerOnceRetentionStrategy(10)

    // Pull strategy
    pullStrategy = DockerImagePullStrategy.PULL_LATEST
    pullTimeout = 300

    // Container settings
    removeVolumes = true
    stopTimeout = 10
}

// Remove existing Docker cloud if present
def cloudFound = false
jenkins.clouds.each { cloud ->
    if (cloud.name == dockerCloudName) {
        jenkins.clouds.remove(cloud)
        cloudFound = true
    }
}

// Add the Docker cloud
jenkins.clouds.add(dockerCloud)
jenkins.save()

println "Docker cloud '${dockerCloudName}' has been " + (cloudFound ? "updated" : "created") + "."
println "Docker image: jenkins-agent:multipurpose"
println "Labels: docker, docker-agent, multipurpose"
println "Docker host: ${dockerHostUrl}"
println ""
println "You can now use these labels in your pipeline jobs to run builds on Docker agents."
