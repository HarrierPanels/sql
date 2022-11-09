PHP based blog CI/CD

1. Build & Testing

a) DB backup by cron:

- Hourly cron job:
0 * * * * $HOME/dbsbkp.sh >>$HOME/sql/mysql/bkp.log 2>>$HOME/sql/mysql/err.log

- Push to GitHub automatically by hook
~/sql/.git/hooks/post-commit

b)

2. Deployment
