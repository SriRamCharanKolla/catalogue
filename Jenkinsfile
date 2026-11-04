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
        stage('Install Dependencies') {
            steps {
                script{
                    sh """
                        npm install
                    """
                }
            }
        }
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
                    // sh """
                    //     docker build -t catalogue:${appVersion} .
                    // """

                    withAWS(credentials: 'aws-creds', region: "${region}") {
                        sh """
                            aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${ACC_ID}.dkr.ecr.${region}.amazonaws.com
                            docker build -t ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion} .
                            docker push ${ACC_ID}.dkr.ecr.${region}.amazonaws.com/roboshop/catalogue:${appVersion}
                        """
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