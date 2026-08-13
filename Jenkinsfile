pipeline {
  agent any

  environment {
    REGISTRY      = '192.168.3.10:5000'
    IMAGE         = "${REGISTRY}/devops-08/juice-shop"
    TAG           = "${env.BUILD_NUMBER}"
    INSTALLER_TAG = "installer-${env.BUILD_NUMBER}"
    APP_HOST      = 'ubuntu@192.168.3.108'
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
        sh '''
          # Build the installer stage explicitly so the SCA stage can reuse it
          # instead of re-exporting the whole layer set a second time.
          docker build --target installer -t "$IMAGE:$INSTALLER_TAG" .
          docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .
        '''
      }
    }

    stage('Smoke test') {
      steps {
        sh '''
          test_name="juice-shop-smoke-${BUILD_NUMBER}"
          trap 'docker rm -f "$test_name" >/dev/null 2>&1 || true' EXIT

          docker run -d --name "$test_name" "$IMAGE:$TAG"

          # Wall-clock deadline: each probe spawns a container, so a plain
          # "30 attempts with sleep 1" is nowhere near 30 seconds.
          deadline=$(( $(date +%s) + 90 ))
          while [ "$(date +%s)" -lt "$deadline" ]; do
            if docker run --rm --network "container:$test_name" node:24 \
                 node -e "fetch('http://127.0.0.1:3000').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" \
                 >/dev/null 2>&1; then
              echo "Smoke test passed"
              exit 0
            fi
            sleep 2
          done

          echo 'Smoke test failed: no HTTP 200 from :3000 within 90s' >&2
          docker logs --tail 100 "$test_name" >&2 || true
          exit 1
        '''
      }
    }

    // DECISION 2026-08-12, owner: <your name>, review by: end of module
    //
    // npm audit is SCA (known CVEs in dependencies), not SAST (analysis of our
    // own source). Named accordingly.
    //
    // Juice Shop is intentionally vulnerable: 7 critical / 19 high / 41 total.
    // Any blocking threshold makes Deploy unreachable, which defeats the point
    // of the exercise. So the scan does not fail the build -- it marks it
    // UNSTABLE and archives the report.
    //
    // This is deliberate and visible (yellow ball), NOT a silently swallowed
    // exit code. On a real project this exception would need a linked ticket
    // and an expiry date, and the threshold would be `high` or stricter.
    stage('Dependency scan (SCA)') {
      steps {
        script {
          def rc = sh(returnStatus: true, script: '''
            set +e
            docker run --rm "$IMAGE:$INSTALLER_TAG" \
              npm audit --omit=dev --audit-level=critical > npm-audit.txt 2>&1
            rc=$?
            docker run --rm "$IMAGE:$INSTALLER_TAG" \
              npm audit --omit=dev --json > npm-audit.json 2>&1
            cat npm-audit.txt
            exit $rc
          ''')
          if (rc != 0) {
            unstable("SCA: findings at or above the 'critical' threshold. " +
                     "Expected for Juice Shop -- see npm-audit.txt.")
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'npm-audit.txt,npm-audit.json',
                           allowEmptyArchive: true, fingerprint: false
        }
      }
    }

    stage('Push') {
      steps {
        sh '''
          docker push "$IMAGE:$TAG"
          docker push "$IMAGE:latest"
        '''
      }
    }

    stage('Deploy to vm-app') {
      steps {
        sshagent(credentials: ['vm-app-08']) {
          sh '''
            ssh -o StrictHostKeyChecking=accept-new "$APP_HOST" \
              "IMAGE='$IMAGE' TAG='$TAG' bash -s" <<'REMOTE'
set -eu

docker pull "$IMAGE:$TAG"

# Keep the previous container around so a bad image can be rolled back.
docker rm -f juice-shop-prev >/dev/null 2>&1 || true
if docker inspect juice-shop >/dev/null 2>&1; then
  docker rename juice-shop juice-shop-prev
  docker stop juice-shop-prev >/dev/null
fi

docker run -d --name juice-shop --restart=unless-stopped \
  -p 3000:3000 "$IMAGE:$TAG"

ok=0
for _ in $(seq 1 45); do
  if curl -fsS -o /dev/null http://127.0.0.1:3000; then ok=1; break; fi
  sleep 2
done

if [ "$ok" -ne 1 ]; then
  echo "Deploy health check failed after 90s -- rolling back" >&2
  docker logs --tail 100 juice-shop >&2 || true
  docker rm -f juice-shop
  if docker inspect juice-shop-prev >/dev/null 2>&1; then
    docker rename juice-shop-prev juice-shop
    docker start juice-shop
    echo "Rolled back to the previous container" >&2
  fi
  exit 1
fi

docker rm -f juice-shop-prev >/dev/null 2>&1 || true
echo "Deployed $IMAGE:$TAG"
REMOTE
          '''
        }
      }
    }
  }

  post {
    unstable {
      echo 'Build is UNSTABLE: the dependency scan found issues at or above ' +
           'the configured threshold. The image was still built and deployed. ' +
           'See the archived npm-audit.txt.'
    }
    failure {
      echo 'Pipeline failed. Check which stage went red -- the dependency scan ' +
           'no longer fails the build, so a red ball here is a real problem.'
    }
    always {
      sh '''
        docker image rm -f "$IMAGE:$INSTALLER_TAG" >/dev/null 2>&1 || true
        docker image prune -f --filter "until=24h" || true
      '''
    }
  }
}
