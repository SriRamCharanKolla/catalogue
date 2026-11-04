# RoboShop Catalogue — DevSecOps Learnings & Troubleshooting Guide (`learning.md`)

This document captures real-world engineering challenges, security pitfalls, root-cause analyses, and architectural solutions encountered while developing the **RoboShop Catalogue DevSecOps CI/CD pipeline**.

---

## 📑 Table of Contents
1. [Issue 1: AWS ECR Repository Naming & Namespace Resolution](#1-issue-1-aws-ecr-repository-naming--namespace-resolution)
2. [Issue 2: Jenkins Secret Text Credential Injection & GitHub API 401 Bad Credentials](#2-issue-2-jenkins-secret-text-credential-injection--github-api-401-bad-credentials)
3. [Issue 3: Dockerfile Hardening & Alpine OS Package Cache Management](#3-issue-3-dockerfile-hardening--alpine-os-package-cache-management)
4. [Issue 4: Trivy Container Image Reference Parsing Failures](#4-issue-4-trivy-container-image-reference-parsing-failures)
5. [Issue 5: Trivy HTML Template Missing vs Standalone Console Table Reporting](#5-issue-5-trivy-html-template-missing-vs-standalone-console-table-reporting)
6. [Issue 6: Trivy Package Scanning Types (`os` vs `library` for npm packages)](#6-issue-6-trivy-package-scanning-types-os-vs-library-for-npm-packages)
7. [Issue 7: Jenkins Pipeline Workspace Hygiene & Disk Exhaustion Mitigation (`cleanWs`)](#7-issue-7-jenkins-pipeline-workspace-hygiene--disk-exhaustion-mitigation-cleanws)

---

## 1. Issue 1: AWS ECR Repository Naming & Namespace Resolution

### Problem Symptom
During `stage('Build Image')`, the pipeline pushed the built Docker container image to AWS ECR and abruptly failed with:
```text
error from registry: The repository with name 'catalogue' does not exist in the registry with id '069416262340'
```

### Root Cause Analysis
In AWS Elastic Container Registry (ECR), repository names can contain multi-level namespaces separated by slashes (e.g., `roboshop/catalogue`, `project/dev/catalogue`).
- The AWS ECR repository was created with the name **`roboshop/catalogue`**.
- In the Jenkinsfile, the docker push command was written as:
  ```groovy
  docker push ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/catalogue:${appVersion}
  ```
- Because Docker separates the registry host from the repository path via the first slash, Docker asked AWS ECR for a repository literally named `catalogue`.
- AWS ECR looked for `catalogue` and failed because only `roboshop/catalogue` existed.

### Remediation
Always include the full repository namespace in the Docker tag and push commands:
```groovy
docker build -t ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion} .
docker push ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion}
```

---

## 2. Issue 2: Jenkins Secret Text Credential Injection & GitHub API 401 Bad Credentials

### Problem Symptom
During `stage('Dependabot Alerts Check')`, the pipeline failed with:
```text
ERROR: GitHub API call failed with HTTP 401. Check token permissions (security_events scope required).
Response: 000 000 000 000{ "message": "Bad credentials", "documentation_url": "https://docs.github.com/rest", "status": "401" }
```
Additionally, the console logs printed:
```text
+ curl -s -w '\n%{http_code}' -H 'Authorization: Bearer curl -L \ -H Accept:' 'application/vnd.github+json \ -H Authorization:' Bearer 'github_pat_11BULUD2A0...
```

### Root Cause Analysis
When creating the `github-token` credential in Jenkins (**Manage Jenkins ➔ Credentials**):
- Instead of pasting **only** the Personal Access Token string (`github_pat_...`), the entire example `curl` snippet from GitHub API documentation was accidentally copied and pasted into the **Secret** field.
- In `Jenkinsfile`, when Groovy expanded `${GITHUB_TOKEN}` inside:
  `-H "Authorization: Bearer ${GITHUB_TOKEN}"`
  The string expanded to:
  `-H "Authorization: Bearer curl -L \ -H Accept: ..."`
- This resulted in mangled HTTP headers, a 401 Unauthorized response from GitHub, and an accidental token leak in the build log because Jenkins credential masking could not match the fragmented token string.

### Remediation
1. **Immediately revoke the leaked token** in GitHub Developer Settings.
2. Generate a new Fine-Grained Personal Access Token with `Dependabot alerts: Read-only` and `security_events` scopes.
3. In Jenkins Credentials, paste **only the raw token string** (e.g. `github_pat_...`) without leading/trailing commands, quotes, or spaces.
4. Use single quotes in Jenkinsfile shell commands (`'''`) with shell environment variables (`$GITHUB_TOKEN`) instead of Groovy string interpolation (`"${GITHUB_TOKEN}"`) to prevent credential exposure warnings.

---

## 3. Issue 3: Dockerfile Hardening & Alpine OS Package Cache Management

### Question / Concept
In [`Dockerfile`](file:///Users/sriramcharankolla/Desktop/DevOps/catalogue/Dockerfile#L14-L15):
```dockerfile
RUN addgroup -S roboshop && adduser -S roboshop -G roboshop && \
    apk --no-cache update && apk --no-cache upgrade
```
*Why is cache removed via `--no-cache`, and is this cache needed in production containers?*

### Technical Explanation
1. **Container Immutability**: Production containers are immutable runtime units. Once a Docker container image is built, no software packages are installed or upgraded dynamically at runtime.
2. **Runtime Independence**: The Node.js application (`node server.js`) runs purely using the Node runtime and dependencies copied from the builder stage (`/app/node_modules`). It never accesses `/var/cache/apk/`.
3. **Layer Size Reduction**: By default, package managers store package repository indexes in `/var/cache/apk/`. Leaving these files inflates the Docker layer by 10MB - 30MB+. The `--no-cache` flag downloads the package index temporarily in memory and discards it after installing packages.
4. **Security Vulnerability Scanning**: Retaining stale package index metadata can cause false positives during container security audits (Trivy / AWS ECR Inspector).

---

## 4. Issue 4: Trivy Container Image Reference Parsing Failures

### Problem Symptom
When running Aqua Trivy in `stage('Trivy Security Scan')`:
```text
FATAL Fatal error run error: image scan error: scan error: unable to initialize a scan service: unable to initialize artifact: unable to initialize container image: failed to parse the image name: could not parse reference: catalogue:069416262340.dkr.ecr.us-east-1.amazonaws.com/roboshop/catalogue:1.0.0
```

### Root Cause Analysis
Docker/OCI image references must strictly adhere to the grammar:
`[REGISTRY/][REPOSITORY]:[TAG]`
- In the Jenkinsfile, the image parameter was specified as:
  `catalogue:${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion}`
- The colon `:` is the delimiter separating the repository name from the tag.
- Trivy parsed `catalogue` as the image name, and treated the remainder (`069416262340.../roboshop/catalogue:1.0.0`) as the tag.
- Because tags cannot contain slashes (`/`), the OCI reference parser failed with `could not parse reference`.

### Remediation
Remove the redundant `catalogue:` prefix and provide the canonical image reference directly:
```groovy
def imageUri = "${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion}"
sh "trivy image --scanners vuln ${imageUri}"
```

---

## 5. Issue 5: Trivy HTML Template Missing vs Standalone Console Table Reporting

### Problem Symptom
When running Trivy with `--format template`:
```text
FATAL Fatal error run error: report error: unable to write results: failed to initialize template writer: error retrieving template from path: open /usr/local/share/trivy/templates/html.tpl: no such file or directory
```

### Root Cause Analysis
- The command `--template @/usr/local/share/trivy/templates/html.tpl` instructed Trivy to read a custom Go template at that file system path.
- Standard Trivy installations (via rpm, binary tarballs, or curl install script) only install the `trivy` executable binary into `/usr/local/bin/trivy`. Template files are not installed by default.
- Furthermore, if lines generating HTML are removed but `publishHTML` is retained with `allowMissing: false`, Jenkins fails the build because `trivy-os-report.html` does not exist.

### Remediation (Two Supported Approaches)
1. **Approach A (Console Table Only - Recommended for CI Logs)**:
   Generate standard table format, print to console, and omit `publishHTML`:
   ```groovy
   sh """
       trivy image \
           --scanners vuln \
           --pkg-types os,library \
           --severity HIGH,CRITICAL \
           --format table \
           --output trivy-report.txt \
           --exit-code 0 \
           ${imageUri}
   """
   sh 'cat trivy-report.txt'
   ```
2. **Approach B (HTML Artifact Publishing)**:
   Download the template dynamically into the build workspace before rendering:
   ```groovy
   sh 'curl -sSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl -o html.tpl'
   sh "trivy image --format template --template @html.tpl --output trivy-report.html ${imageUri}"
   ```

---

## 6. Issue 6: Trivy Package Scanning Types (`os` vs `library` for npm packages)

### Question / Concept
*Why were npm code dependencies not showing up in the Trivy scan table?*

### Technical Explanation
Trivy distinguishes between two primary package target categories:
1. **`os`**: Operating system packages managed by system package managers (Alpine `apk`, Debian `dpkg`, RHEL `rpm`).
2. **`library`**: Application programming language dependencies (Node.js `package.json` / `node_modules`, Python `pip`, Java `pom.xml`, Go modules).

When `--pkg-types os` was passed, Trivy explicitly excluded all application libraries (`library`), ignoring npm dependencies like `node-tar` or `express-pino-logger`.
To scan both OS and third-party application libraries, configure:
```bash
--pkg-types os,library
```

---

## 7. Issue 7: Jenkins Pipeline Workspace Hygiene & Disk Exhaustion Mitigation (`cleanWs`)

### Problem Symptom
Build agent servers frequently run out of disk space, displaying:
`Disk space is below threshold of 1.00 GiB. Only 1015.76 MiB left on /var/lib/jenkins.`

### Technical Explanation
- Each pipeline build clones git repositories, downloads third-party packages (`node_modules`), builds Docker layers, and outputs test reports.
- Without explicit post-build cleanup, multiple consecutive builds accumulate gigabytes of stale files.
- Stale files from prior builds can also create "phantom builds" where obsolete files mask real build failures.

### Solution: `cleanWs()` in `post { always { ... } }`
The Workspace Cleanup plugin step `cleanWs()` ensures a clean slate:
```groovy
post { 
    always { 
        echo 'Pipeline finished. Cleaning workspace...'
        cleanWs()
    }
}
```
Because it is placed in the `always` block, it executes regardless of whether the build succeeded, failed, or was terminated, guaranteeing zero lingering workspace storage.

