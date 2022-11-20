#!/bin/bash

# Global vars
dir="$HOME/sql"
host="localhost"
date=$(date +%Y-%m-%d-)

dbsbkp() {
dblist=$(echo show databases | mysql -h $host | sed '1d' | 
grep -Ev '(^(mysql|sys|information_schema|performance_schema)$)')
for db in $dblist; do
mysqldump --add-drop-database --databases $db | gzip -9 > $dir/mysql/$date$db.sql.gz  
done
}

cmsbkp() {
cd /var/www && tar -cvzf $dir/mysql/"$date"cms.tar.gz *
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
git add . && git commit -m "DB's Backup & Remove Old" 
}

# Backing up DB's
sudo service mysqld status >/dev/null 2>&1 && dbsbkp || 
sudo service mysqld start >/dev/null 2>&1 && dbsbkp

# Backing up CMS
sudo service httpd status >/dev/null 2>&1 && cmsbkp ||
sudo service httpd start >/dev/null 2>&1 && cmsbkp

# Removing older than 30 days
rmold

# Repo update
rpupd 
