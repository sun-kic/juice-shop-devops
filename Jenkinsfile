pipeline {
  agent any

  environment {
    REGISTRY = '192.168.3.10:5000'
    IMAGE    = "${REGISTRY}/devops-08/juice-shop"
    TAG      = "${env.BUILD_NUMBER}"
  }

  options {
    timeout(time: 40, unit: 'MINUTES')     // a cold build is ~10 min; leave headroom for the queue
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  // Webhooks cannot reach this network -- vm-ci is on a private address.
  triggers { pollSCM('H/2 * * * *') }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build image') {
      steps {
        sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
      }
    }

    stage('Push') {
      steps {
        sh 'docker push $IMAGE:$TAG && docker push $IMAGE:latest'
      }
    }
  }

  post {
    always {
      sh 'docker image prune -f --filter "until=24h" || true'
    }
  }
}
