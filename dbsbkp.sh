#!/bin/bash

# Global vars
dir="$HOME/sql"
host="localhost"
date=$(date +%Y-%m-%d-)

dbsbkp() {
cd $dir/mysql
dblist=$(echo show databases | mysql -h $host | sed '1d' | 
grep -Ev '(^(mysql|sys|information_schema|performance_schema)$)')
for db in $dblist; do
mysqldump $db > $db.sql && tar -czf $date$db.sql.tar.gz $db.sql && 
rm $db.sql 
done
}

rmold() {
cd $dir/mysql
current=$(echo $date | tr -d '-')
for i in $(ls -laf *.gz); do 
old=$(echo $i | cut -d "-" -f 1-3 | tr -d "-") 
[[ $(($current-$old)) -gt 100 ]] && git rm $i
done
}

rpupd() {
cd $dir
git add . && git commit -m "DB's Backup & Remove Old" && 
git push --all origin >/dev/null 2>&1
}

# Backing up DB's
sudo service mysqld status >/dev/null 2>&1 && dbsbkp || 
sudo service mysqld start >/dev/null 2>&1 && dbsbkp

# Removing older than 30 days
rmold

# Repo update
rpupd 
