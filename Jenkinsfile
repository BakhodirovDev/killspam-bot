// CI/CD for killspam-bot: build -> test -> deploy (Docker Compose).
//
// Secrets are NOT in git. The entire .env lives in Jenkins as a managed file
// (Manage Jenkins > Managed files, "Config File Provider" plugin) and is dropped
// into the workspace at build time, then consumed by docker-compose's env_file.
//
// Prerequisites on the agent:
//   - Docker Engine + `docker compose` v2
//   - Config File Provider plugin, with a managed file whose ID matches ENV_FILE_ID
//     below. Its content is a normal .env (see .env.example). For the bundled
//     Postgres, DATABASE_URL must be:
//       DATABASE_URL=postgresql://spam:spam@db:5432/spam_bot?sslmode=disable

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
  }

  environment {
    IMAGE       = 'killspam-bot'
    TAG         = "${env.BUILD_NUMBER}"
    ENV_FILE_ID = 'killspam-bot-env'   // <-- your managed file's ID
    COMPOSE     = 'docker compose -p killspam'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Inject .env') {
      steps {
        configFileProvider([configFile(fileId: env.ENV_FILE_ID, targetLocation: '.env')]) {
          sh 'test -s .env && echo ".env injected: $(grep -c . .env) non-empty lines"'
        }
      }
    }

    stage('Build image') {
      steps {
        sh 'docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .'
      }
    }

    stage('Test') {
      // Run the suite inside the freshly built image, so tests exercise the exact
      // dependency set that ships. Tests use in-memory sqlite (tests/conftest.py) —
      // no Postgres, no secrets. -u root so pytest can be pip-installed on the fly.
      steps {
        sh '''
          docker run --rm -u root -e DATABASE_URL=sqlite:// "$IMAGE:$TAG" \
            sh -c "pip install --no-cache-dir --quiet pytest && python -m pytest -q"
        '''
      }
    }

    stage('Deploy') {
      // No branch gate: this single-branch "Pipeline from SCM" job only ever builds
      // the configured branch (master). env.BRANCH_NAME is unset here (that's a
      // Multibranch-only var), so a `when { branch ... }` would skip forever.
      steps {
        // compose pulls image: killspam-bot:latest (just built) + env_file: .env.
        // `up -d` recreates the bot and starts Postgres if it isn't already running.
        sh '$COMPOSE up -d --remove-orphans'
        sh '''
          # Poll the container's own HEALTHCHECK (Dockerfile) via docker inspect —
          # works regardless of whether the agent can reach the published port.
          cid=$($COMPOSE ps -q bot)
          echo "Waiting for bot ($cid) to become healthy ..."
          for i in $(seq 1 30); do
            status=$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo missing)
            if [ "$status" = healthy ]; then echo "bot is healthy"; exit 0; fi
            if [ "$status" = missing ]; then echo "bot container gone"; break; fi
            sleep 2
          done
          echo "bot not healthy in time (last status: $status) — recent logs:"
          $COMPOSE logs --tail=80 bot
          exit 1
        '''
      }
    }
  }

  post {
    success { echo "Deployed ${IMAGE}:${TAG}" }
    failure { sh '$COMPOSE ps || true' }
    always  { sh 'docker image prune -f >/dev/null 2>&1 || true' }
    cleanup { sh 'rm -f .env' }   // never leave secrets in the workspace
  }
}
