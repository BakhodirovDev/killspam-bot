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
      when { anyOf { branch 'main'; branch 'master' } }
      steps {
        // compose pulls image: killspam-bot:latest (just built) + env_file: .env.
        // `up -d` recreates the bot and starts Postgres if it isn't already running.
        sh '$COMPOSE up -d --remove-orphans'
        sh '''
          echo "Waiting for /health ..."
          for i in $(seq 1 30); do
            if curl -fsS http://localhost:6050/health >/dev/null 2>&1; then
              echo "bot is healthy"; exit 0
            fi
            sleep 2
          done
          echo "health check did not pass in time — recent bot logs:"
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
