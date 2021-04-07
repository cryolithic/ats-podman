pipeline {
  agent { label 'podman' }

  parameters {
    string(name:'version', defaultValue:'16.3.0', description:'target version')
    string(name:'distribution', defaultValue:'current', description:'target distribution')
  }

  triggers {
    cron("@daily")
  }

  stages {

    stage('Update subtrees') {
      steps {
	sh "sudo ./bin/ats-wrapper.sh ${version} ${distribution}"
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
