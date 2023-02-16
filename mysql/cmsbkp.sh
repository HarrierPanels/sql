#!/bin/bash

# Global vars
dir="$HOME/sql"
host="localhost"
date=$(date +%Y-%m-%d-)
instance_id="i-0fe7dc1f6f9c11cc2"
ec2_info() {
ip=$(/usr/local/bin/aws ec2 describe-instances \
    --instance-ids $instance_id \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --o text)
state=$(/usr/local/bin/aws ec2 describe-instances \
   --instance-ids $instance_id \
   --query "Reservations[*].Instances[*].[State.Name]" \
   --o text)
}
dir_t="$HOME/terraform/t9"
region=$(/usr/local/bin/aws configure get region)
url="https://ec2."$region".amazonaws.com"
filename=$(basename -- "$0" | cut -d '.' -f 1)
ans_dir="$HOME/$filename"

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

init() {
sleep 90 &
p=$!
f="/ | \\ -"

while kill -0 $p >/dev/null 2>&1; do
for i in $f; do
printf "\r\033[1;32m$i Initializing ...\e[0m"
sleep 0.5
done
done
printf "\n"
}

retry() {
function="$@"
count=0
max=100
sleep=5

while :; do
$function && break
if [ $count -lt $max ]; then
((count++))
echo "Command failed, retrying after $sleep seconds... $count/$max"
sleep $sleep
continue
fi
echo "Command failed, out of retries." && exit 1
done
}

jenkinscheck() {
curl -Ls $1 | grep "Authentication required" >/dev/null 2>&1
[ $? -ne 0 ] && echo -e "\033[1;31mJenkins not ready! \e[0m" && return 1
echo -e "\033[1;32mJenkins is up! \e[0m"
}

awscheck() {
curl -ILs $1 | grep "AmazonEC2" >/dev/null 2>&1
[ $? -ne 0 ] && echo -e "\033[1;31mAWS unreachable! \e[0m" && return 1
echo -e "\033[1;32mAWS OK\e[0m"
}

statecheck() {
i=1
until [[ $state =~ "stopped" ]]; do
retry awscheck $url && ec2_info
printf "\r$i sec "
((i++))
sleep 1
continue
done
rm -rf $ans_dir 2>/dev/null
printf "\n"
echo "Done! "
}

# Ansible Playbook
playbook() {
cat <<EOF >"$ans_dir"/"$filename".yml
---

- name: Crontab / Ansible CI/CD 
  hosts: $filename 
  gather_facts: False
  become: yes

  tasks:

    - name: Set GitHub Webhook
      become_user: ec2-user
      ansible.builtin.shell: |
        gh webhook forward --repo HarrierPanels/sql \ 
          --events=push --url="http://localhost:8080/github-webhook/"
        echo 'Webhook set!'
      async: 45
      poll: 0

    - name: Git push at localhost 
      become_user: a
      ansible.builtin.shell: |
        cd $dir
        git add . && git commit -m "Backup & Remove Old by Cron / Ansible"
      register: git
      delegate_to: localhost

    - name: Git push
      ansible.builtin.debug:
        var: git
EOF
}

# Ansible Setup
ans_setup() {
cat <<EOF >"$ans_dir"/ansible.cfg
[defaults]
host_key_checking    = false
inventory            = $filename.txt
deprecation_warnings = False
EOF

cat <<EOF >"$ans_dir"/"$filename".txt 
[$filename]
$ip

[local]
localhost ansible_host=localhost
EOF

cat <<EOF >"$ans_dir"/group_vars/"$filename" 
---
ansible_user: ec2-user
ansible_ssh_private_key: ~/.ssh/j2.pem
EOF

cat <<EOF >"$ans_dir"/group_vars/local 
---
ansible_user: a
ansible_ssh_private_key: ~/.ssh/j2.pem
EOF

playbook
}

# Crontab / Terraform / Ansible / Jenkins CI/CD
cicd_toolchain() {
mkdir -p "$ans_dir"/group_vars &&
terraform -chdir="$dir_t" apply -auto-approve
init && retry awscheck $url && ec2_info
retry jenkinscheck "$ip":8080
echo "Configuring..."
ans_setup && sleep 5
ansible-playbook "$ans_dir"/*yml -i "$ans_dir"/*txt \
   --ssh-common-args='-o StrictHostKeyChecking=no' \
   -e "ansible_python_interpreter=/usr/bin/python3" -b -vvv
retry awscheck $url && ec2_info && statecheck 
}

# Backing up DB's
sudo service mysqld status >/dev/null 2>&1 && dbsbkp || 
sudo service mysqld start >/dev/null 2>&1 && dbsbkp

# Backing up CMS
sudo service httpd status >/dev/null 2>&1 && cmsbkp ||
sudo service httpd start >/dev/null 2>&1 && cmsbkp

# Removing older than 30 days
rmold

# CI/CD
cicd_toolchain
