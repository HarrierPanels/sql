pipeline {
    agent {label 'ec2-plugin'}

    stages {
        stage('Build') {
            steps {
				echo '--------START--------'
                sh label: 'Build', script: '''
					latestbkp() { ls *$1* | sort -nr | head -n1; }
					cd /home/ec2-user
					git clone https://github.com/HarrierPanels/sql.git
					cd sql/mysql
					cp $(latestbkp cms_) docker/mysql/bkp
					cp $(latestbkp cms.) docker/php/bkp
cat << EOF >docker/php/bkp/test.php
<?php include('includes/db.php');
\\$user=\\$_GET['user'];
\\$password=\\$_GET['password'];
\\$count=mysqli_query(\\$conn,"select * from users where user='\\$user' and password='\\$password'");
if (!\\$count || mysqli_num_rows(\\$count) == 0) {
exit("Login failed!");
} else {
echo 'Hello ' .\\$user. '!<br /><br />';
if (!(\\$result=mysqli_query(\\$conn,"show tables where tables_in_cms_db <> 'users'")))
printf("Error: %s\n", mysqli_error(\\$conn));
echo "CMS User Panel<br /><br />";
while(\\$row = mysqli_fetch_row( \\$result ))
echo \\$row[0]. '<br />';
\\$count -> free_result();
\\$result -> free_result();
\\$conn->close();
}
?>
EOF
cat << EOF >docker/mysql/bkp/.my.cnf
[mysql]
user=a
password=7Ujm8ik,9ol.

[mysqldump]
user=a
password=7Ujm8ik,9ol.
EOF
					cd docker
					docker-compose up -d
                '''
				echo '--------SUCCESS--------'

            }
        }
        stage('Test') {
            steps {
				echo '--------START--------'                
				sh label: 'Test Docker', script: '''
                    for i in {10..1}; do sleep 10
					curl -Ls localhost
						if [ $? -eq 0 ]; then
						echo 'Docker is up!'
						break
						fi
					echo "$((i-1)) atempts left!"
					echo '--------------------'
						if [ $i -eq 2 ]; then
						echo 'FATAL: Docker failed to start!'
						echo '--------FAILURE--------'
						exit 1
						fi
					done
                '''
				echo '--------Test DB--------'
				sh label: 'Test DB', script: '''
					for i in {10..1}; do sleep 10 && echo 'Connecting to DB ...'
					test="localhost/test.php?user=test&password=12345"
                    testdb=$(curl -Ls $test | grep -oP "test" | wc -l)
					if [ $testdb -eq 1 ]; then
                    echo 'Test DB passed!'
					break
					fi
					echo "$((i-1)) atempts left!"
					echo '--------------------'
						if [ $i -eq 2 ]; then
						echo 'FATAL: Failed to Connect to DB!'
						echo '--------FAILURE--------'
						exit 1
						fi					
					done
                '''				
				echo '--------Test CMS--------'
				sh label: 'Test CMS', script: '''
					serverlive="172.31.88.211/articles.php"
					dockertest="localhost/articles.php"
					serverdate=$(curl -Ls $serverlive | grep -oP " *[0-9]+[-][0-9]+[-][0-9]+ [0-9]+:[0-9]+:[0-9]+" | head -n 1 | tr -d ' -' | tr -d ':')
					dockerdate=$(curl -Ls $dockertest | grep -oP " *[0-9]+[-][0-9]+[-][0-9]+ [0-9]+:[0-9]+:[0-9]+" | head -n 1 | tr -d ' -' | tr -d ':')
					echo "---------------------"
					if [[ $(($dockerdate-$serverdate)) -lt 0 ]]; then
					echo 'Fatal: No rollback scheduled!'
					echo '--------FAILURE--------'					
					exit 1
					elif [[ $(($dockerdate-$serverdate)) -eq 0 ]]; then
					echo 'Warning: No new articles added!'
					else echo 'Update applied successfuly!'
					fi
                '''
				echo '--------SUCCESS--------'                	
            }
        }
         stage('Deploy') {
            steps {
                sh 'mv /home/ec2-user/sql/mysql/docker/mysql/bkp/*cms_* .'
		sh 'mv /home/ec2-user/sql/mysql/docker/php/bkp/*cms.* .'
                sshPublisher(
                continueOnError: false, 
                failOnError: true,
                publishers: [
                sshPublisherDesc(
                configName: "server-live",
                transfers: [
					sshTransfer(sourceFiles: '*cms*'),
					sshTransfer(execCommand: 'rm -rf /var/www/html/*'),
					sshTransfer(execCommand: 'gunzip < bkp/*.sql.gz | mysql'),
					sshTransfer(execCommand: 'tar -xzvf bkp/*.tar.gz -C /var/www'),
					sshTransfer(execCommand: 'rm bkp/*'),
				],			
                verbose: true
                        )
                    ]
                )
            }
        }               
    }
}
