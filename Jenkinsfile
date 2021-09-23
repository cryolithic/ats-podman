void run_ats(distribution, version, extra_dev_distribution) {
  sh "sudo ./bin/jenkins-ats-wrapper.sh -e '${extra_dev_distribution}' ${distribution} ${version}"
}

pipeline {
  agent none

  parameters {
    string(name:'version', defaultValue:'16.4.0', description:'target version')
    string(name:'distribution', defaultValue:'current', description:'target distribution')
    string(name:'extra_dev_distribution', defaultValue:env.branch_NAME, description:'extra dev distribution (for PRs)')
  }

  triggers {
    parameterizedCron('''
      0 23 * * *
      0 01 * * * %version=16.3.0;distribution=current-release163
      ''')
  }

  stages {

    stage('Run ATS') {
      agent { label 'podman' }
      steps {
        run_ats(params.distribution, params.version, params.extra_dev_distribution)
      }

      post {
	changed {
	  script {
	    // set result before pipeline ends, so emailer sees it
	    currentBuild.result = currentBuild.currentResult
          }
         emailext(to:'seb@untangle.com', subject:"${env.JOB_NAME} #${env.BUILD_NUMBER}: ${currentBuild.result}", body:"${env.BUILD_URL}")
//         slackSend(channel:"#team_engineering", message:"${env.JOB_NAME} #${env.BUILD_NUMBER}: ${currentBuild.result} at ${env.BUILD_URL}")
	}
      }
    }
  }
}
