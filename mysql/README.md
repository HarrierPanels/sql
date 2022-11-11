PHP based CMS: Aviation blog Template CI/CD

1. Build

a) DB & coding automatic backup by cron:

- MySQL no password promt login:
~/.my.cnf

- Hourly cron job:
0 * * * * $HOME/cmsbkp.sh >>$HOME/sql/mysql/bkp.log 2>>$HOME/sql/mysql/err.log

- Commit & Push to GitHub automatically by hook:
~/sql/.git/hooks/post-commit

2. Testing DB & Code on AWS EC2
3. Deployment to Live EC2 Server 
