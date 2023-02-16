[![HitCount](https://hits.dwyl.com/HarrierPanels/sql.svg?style=flat&show=unique)](http://hits.dwyl.com/HarrierPanels/sql)
<br>
PHP based CMS: Aviation blog Template CI/CD

###### Prerequisites
- Content Management Team (to add content)
- Developer Team (to add more features to CMS)
- Design Team (to add more visual effects, etc.)
- Servers: Local LAMP server, GitHub
##
- DevOps (CI/CD)
- Ansible / Terraform controller local node, Jenkins controller (AWS EC2)
- Toolchain: AWS CLI, GH CLI, Terraform, Ansible, Docker, Jenkins, Crontab
- Production Team
- Live LAMP server (AWS EC2)

[Refactoring (Beta)](https://github.com/HarrierPanels/sql/blob/Beta/mysql/README.md)

It includes 4 stages: Pre-Build - the Jenkins server is started up by Terraform using Null Resource:
```
provider "aws" {}

resource "aws_instance" "jenkins" {
  ami                         = "ami-xxxxxxxxxxx"
  instance_type               = "t2.micro"
  tags = {
    Name = "jenkins"
  }
}
resource "null_resource" "action_instance" {
  provisioner "local-exec" {
    on_failure  = fail
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
        echo "Starting instance having id ${aws_instance.jenkins.id} .................."
    # Start instance using AWS CLI
    /usr/local/bin/aws ec2 start-instances --instance-ids ${aws_instance.jenkins.id} --profile your_profile
        
        echo "******** Started *******"
     EOT
  }
#   this setting will trigger script every time, change it if needed
  triggers = {
    always_run = "${timestamp()}"
  }

}
```
Jenkins has the necessary preset of plugins, credentials and agents to run a pre-configured pipeline to Build, Test, & Deploy. The pipeline is triggered by GitHub Webhook that is set by Amsible using the GH CLI webhook forwarding feature (Beta):
```
gh webhook forward --events=push --repo=HarrierPanels/sql \ 
                --url="http://localhost:8080/github-webhook/"
```
Then DB & CMS coding backup is carried out locally by Cron as well as git push. 

Triggered out by GitHub Webhook a declarative pipeline (Jenkinsfile) job is started by the Jenkins controller using as its agents EC2 instances started and terminated when the job is done by AWS EC2 Plugin.

1. Pre-Build

a) DB & coding automatic backup by cron:
 - MySQL no password promt login:
   ~/.my.cnf
 - Hourly cron job:
   0 * * * * $HOME/cmsbkp.sh >>$HOME/sql/mysql/bkp.log 2>>$HOME/sql/mysql/err.log
 - Commit & Push to GitHub automatically by hook:
   ~/sql/.git/hooks/post-commit

2. Build

a) Step 1
 - the repo is git cloned

b) Step 2
 - the DB & PHP coding backup files as well as generated files required for testing are placed in the docker folder.

c) Step 3
- a Docker LAMP stack is build and started by docker-compose

3. Testing DB & Code

a) Step 1 'Docker test':
 - Check if the docker build LAMP server is ready for testing

b) Step 2 'DB test':
- DB is tested for accessibility by checking if the user 'test' has access to the CMS control Panel with password '12345'

c) Step 3 'CMS test':
- CMS is test checked if new articles are added to the template blog. The test will fail if the latest article publication date is earlier than that on the Live server.

4. Deployment to Live EC2 Server

a)  Step 1
 - Preparing tested files to deploy

b) Step 2
 - Transfering files using Publish Over SSH Plugin

c) Step 3
 - Deploying DB & Coding part

d) Step 4 
 - Cleaning up transferred files 

If the job fails the Jenkins server will be ready for manual maintenance. If it is successful the next job run on a pre-set local agent would shut it down.
