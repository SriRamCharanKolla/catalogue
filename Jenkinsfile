pipeline {
    agent {
        node {
            label 'roboshop' 
        } 
    }
    environment {
        appVersion = ""
        ACC_ID = "069416262340"
        region = "us-east-1"
    }
    options {
        //disableConcurrentBuilds()
        timeout(time: 5, unit: 'MINUTES')
    }
    stages {
        stage('Read version'){
            steps {
                script {
                    // Load and parse the JSON file
                    def packageJson = readJSON file: 'package.json'
                    
                    // Access fields directly
                    appVersion = packageJson.version
                    echo "Building version ${appVersion}"
                }
            }
        }
        // stage('Install Dependencies') {
        //     steps {
        //         script{
        //             sh """
        //                 npm install
        //             """
        //         }
        //     }
        // }
        // stage('SonarQube Analysis') {
        //     steps {
        //         script {
        //             def scannerHome = tool name: 'sonar-8' // agent configuration
        //             withSonarQubeEnv('sonar-server') { // analysing and uploading to server
        //                 sh "${scannerHome}/bin/sonar-scanner"
        //             }
        //         }
        //     }
        // }
        // stage("Quality Gate") {
        //     steps {
        //       timeout(time: 1, unit: 'HOURS') {
        //         waitForQualityGate abortPipeline: true
        //       }
        //     }
        // }
        stage('Dependabot Alerts Check') {
            steps {
                withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
                    script {
                        def owner = 'SriRamCharanKolla'
                        def repo  = 'catalogue'

                        def response = sh(
                            script: """
                                curl -s -w "\\n%{http_code}" \\
                                    -H "Authorization: Bearer $GITHUB_TOKEN" \\
                                    -H "Accept: application/vnd.github+json" \\
                                    -H "X-GitHub-Api-Version: 2022-11-28" \\
                                    "https://api.github.com/repos/${owner}/${repo}/dependabot/alerts?severity=high,critical&state=open&per_page=100"
                            """,
                            returnStdout: true
                        ).trim()

                        def parts      = response.tokenize('\n')
                        def httpStatus = parts[-1].trim()
                        def body       = parts[0..-2].join('\n')

                        if (httpStatus != '200') {
                            error "GitHub API call failed with HTTP ${httpStatus}. Check token permissions (security_events scope required).\nResponse: ${body}"
                        }

                        def alerts = readJSON text: body

                        if (alerts.size() == 0) {
                            echo "✅ No HIGH or CRITICAL Dependabot alerts found. Pipeline continues."
                        } else {
                            echo "🚨 Found ${alerts.size()} HIGH/CRITICAL Dependabot alert(s):"
                            alerts.each { alert ->
                                def pkg      = alert.security_vulnerability?.package?.name ?: 'unknown'
                                def severity = alert.security_advisory?.severity?.toUpperCase() ?: 'UNKNOWN'
                                def summary  = alert.security_advisory?.summary ?: 'No summary'
                                def fixedIn  = alert.security_vulnerability?.first_patched_version?.identifier ?: 'No fix available'
                                echo "  ❌ [${severity}] ${pkg} — ${summary} (Fixed in: ${fixedIn})"
                            }
                            error "Pipeline failed: ${alerts.size()} HIGH/CRITICAL Dependabot alert(s) detected."
                        }
                    }
                }
            }
        }
        stage('Build Image') {
            steps {
               script{
                    withAWS(credentials: 'aws-creds', region: "${region}") {
                        sh """
                            docker build -t ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion} .
                            docker push ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion}
                        """
                    }
                }
            }
        }
        // stage('Trivy Security Scan') {
        //     steps {
        //         script {
        //             def imageUri = "${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion}"

        //             // 1. Generate table report on Agent disk
        //             sh """
        //                 trivy image \
        //                     --scanners vuln \
        //                     --pkg-types os,library \
        //                     --severity HIGH,MEDIUM \
        //                     --format table \
        //                     --output trivy-report.txt \
        //                     --exit-code 0 \
        //                     ${imageUri}
        //             """

        //             // 2. Print table directly in Jenkins Console Output
        //             sh 'cat trivy-report.txt'

        //             // 3. Fail pipeline if vulnerabilities found (Exit code 1)
        //             def scanResult = sh(
        //                 script: """
        //                     trivy image \
        //                         --scanners vuln \
        //                         --pkg-types os,library \
        //                         --severity HIGH,MEDIUM \
        //                         --format table \
        //                         --exit-code 1 \
        //                         --quiet \
        //                         ${imageUri}
        //                 """,
        //                 returnStatus: true
        //             )

        //             if (scanResult != 0) {
        //                 error "🚨 Trivy found HIGH/MEDIUM vulnerabilities. Pipeline failed."
        //             } else {
        //                 echo "✅ No HIGH or MEDIUM vulnerabilities found. Pipeline continues."
        //             }
        //         }
        //     }
        // }
        stage('Trivy Dockerfile Scan') 
        {
            steps {
                script {
                    sh """
                        trivy config \
                            --severity HIGH,MEDIUM \
                            --format table \
                            --output trivy-dockerfile-report.txt \
                            Dockerfile
                    """

                    sh 'cat trivy-dockerfile-report.txt'

                    def scanResult = sh(
                        script: """
                            trivy config \
                                --severity HIGH,MEDIUM \
                                --exit-code 1 \
                                --format table \
                                Dockerfile
                        """,
                        returnStatus: true
                    )

                    if (scanResult != 0) {
                        error "🚨 Trivy found HIGH/MEDIUM misconfigurations in Dockerfile. Pipeline failed."
                    } else {
                        echo "✅ No HIGH or MEDIUM Dockerfile misconfigurations found. Pipeline continues."
                    }
                }
            }
        }
    }

    // post build
    post { 
        always { 
            echo 'I will always say Hello again!'
            cleanWs()
        }
        success {
            echo "pipeline success"
        }
        failure {
            echo "pipeline failure"
        }
    }
}