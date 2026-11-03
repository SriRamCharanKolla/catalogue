pipeline {
    agent {
        node {
            label 'roboshop' 
        } 
    }
    environment {
        appVersion = ""
    }
    options {
        //disableConcurrentBuilds()
        timeout(time: 5, unit: 'MINUTES')
    }
    /* parameters {
        string(name: 'PERSON', defaultValue: 'Mr Jenkins', description: 'Who should I say hello to?')
        text(name: 'BIOGRAPHY', defaultValue: '', description: 'Enter some information about the person')
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Toggle this value')
        choice(name: 'CHOICE', choices: ['One', 'Two', 'Three'], description: 'Pick something')
        password(name: 'PASSWORD', defaultValue: 'SECRET', description: 'Enter a password')
    } */
    stages {
        stage('Read version'){
            steps {
                script {
                    // Load and parse the JSON file
                    def packageJson = readJSON file: 'package.json'
                    
                    // Access fields directly
                    appVersion = packageJson.version
                    echo "Building ${appName} version ${appVersion}"
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
        stage('Build Image') {
            steps {
               script{
                    sh """
                        docker build -t catalogue:${appVersion}
                    """
                }
            }
        }
    }

    // post build
    post { 
        always { 
            echo 'I will always say Hello again!'
        }
        success {
            echo "pipeline success"
        }
        failure {
            echo "pipeline failure"
        }
    }
}