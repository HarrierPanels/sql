PHP based CMS: Aviation blog Template CI/CD

[Refactoring (Beta)](/tree/Beta/mysql/README.md)

It includes 4 stages: Pre-Build - DB & CMS coding backup carried out locally by cron; Build, Test, & Deploy - by Jenkins. 

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
