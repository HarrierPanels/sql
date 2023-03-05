#!/bin/bash

# Global vars
dir="$HOME/sql"
host="localhost"
date=$(date +%Y-%m-%d-)
filename=$(basename -- "$0" | cut -d '.' -f 1)
iac_dir="$HOME/$filename"
prod_live_id="i-XXXXXXX_NOT_EXPOSED_XXXXXXX"
ec2_info() {
instance_id=$(terraform -chdir=$iac_dir output | head -n 1 | 
cut -d '=' -f 2 | cut -d ']' -f 1 | tr -d " ,\"")
public_ip=$(terraform -chdir=$iac_dir output | 
tail -n 1 | cut -d "=" -f2 | tail -n 1 | tr -d " ,\"")
state=$(/usr/local/bin/aws ec2 describe-instances \
   --instance-ids $instance_id \
   --query "Reservations[*].Instances[*].[State.Name]" \
   --o text)
status=$(/usr/local/bin/aws ec2 describe-instance-status \
   --instance-id $instance_id \
   --query "InstanceStatuses[*].[InstanceStatus.Details[*].[Status]]" \
   --o text)
}
region=$(/usr/local/bin/aws configure get region)
url="https://ec2."$region".amazonaws.com"

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
terraform -chdir="$iac_dir" destroy -auto-approve
sleep 60 && rm -rf $iac_dir 2>/dev/null
printf "\n"
echo "CI/CD Task complete! "
}

statuscheck() {
i=1
until [[ $status =~ "passed" ]]; do
retry awscheck $url && ec2_info
printf "\r$i sec "
((i++))
sleep 1
continue
done
printf "\n"
echo "Server ready for Ansible setup! "
}

# Terraform Setup
trf_setup() {
cat <<EOF >"$iac_dir"/"$filename".tf
provider "aws" {}

resource "aws_instance" "jenkins_docker" {
  ami                         = data.aws_ami.AL2_latest.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.subnet-jenkins_docker.id
  vpc_security_group_ids      = [aws_security_group.sg-jenkins_docker.id]
  key_name                    = "j2"
  tags = {
    Name = "Jenkins-Docker"
  }
}

data "aws_ami" "AL2_latest" {
  owners = ["137112412989"]
  most_recent = true
  filter {
    name = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "avail" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_vpc" "Dev_vpc" {
  tags = {
    Name = "Dev"
  }
}

resource "aws_subnet" "subnet-jenkins_docker" {
  vpc_id = data.aws_vpc.Dev_vpc.id
  availability_zone = data.aws_availability_zones.avail.names[0]
  cidr_block = "172.31.96.0/24"
  tags = {
    Name = "Subnet-in-\${data.aws_availability_zones.avail.names[0]}"
    Account = "Subnet in acc. \${data.aws_caller_identity.current.account_id}"
    Region = data.aws_region.current.description
  }
}

resource "aws_security_group" "sg-jenkins_docker" {
  name        = "sg_jenkins_docker"
  description = "Allow TCP/SSH inbound/outbound traffic"

        dynamic "ingress" {
                for_each = ["80", "8080", "443"]
                        content {
                                from_port = ingress.value
                                to_port = ingress.value
                                protocol = "tcp"
                                cidr_blocks = ["0.0.0.0/0"]
                        }
        }

  ingress {
    description      = "SSH from IP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["178.150.20.173/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tcp_ssh"
  }

}

resource "aws_security_group" "sg-jenkins_docker_ec2_plugin_slave" {
  name        = "sg_jenkins_docker_ec2_plugin_slave"
  description = "Allow TCP/SSH inbound/outbound traffic"

        dynamic "ingress" {
                for_each = ["80", "8080", "443"]
                        content {
                                from_port = ingress.value
                                to_port = ingress.value
                                protocol = "tcp"
                                cidr_blocks = ["0.0.0.0/0"]
                        }
        }

  ingress {
    description      = "SSH from Jenkins Docker master"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    security_groups  = [aws_security_group.sg-jenkins_docker.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tcp_ssh_slave"
  }

}
EOF

cat <<EOF >"$iac_dir"/outputs.tf
output "EC2_ID" {
  description="Display EC2 ID"
  value=aws_instance.jenkins_docker.id
}

output "EC2_Public_IP" {
  description="Display EC2 Public IP"
  value=aws_instance.jenkins_docker.public_ip
}
EOF
}

# Ansible Playbook
playbook() {
cat <<EOF >"$iac_dir"/"$filename".yml
---

- name: Crontab / Terraform /Ansible CI/CD 
  hosts: $filename 
  gather_facts: False
  become: yes
  vars:
    dest: /home/ec2-user/jcheck.sh
    aws_conf: /home/ec2-user/.aws/config
    aws_creds: /home/ec2-user/.aws/credentials 
    ssh_dir: /home/ec2-user/.ssh
    auth_key: /home/ec2-user/.ssh/authorized_keys
    dest_token: /home/ec2-user/.ssh/token

  tasks:

    - name: Install Java
      ansible.builtin.shell:
        amazon-linux-extras install java-openjdk11 -y

    - name: Download awscliv2 installer
      ansible.builtin.shell:
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \\                   -o "awscliv2.zip"
      ignore_errors: yes

    - name: Run the installer
      ansible.builtin.shell: |
        unzip awscliv2.zip
        ./aws/install
      register: aws_install

    - name: Show installer output
      ansible.builtin.debug:
        var: aws_install

    - name: Add GH Repo
      ansible.builtin.shell: |
        yum-config-manager --add-repo \\
           https://cli.github.com/packages/rpm/gh-cli.repo

    - name: Install / Upgrade Python / GH / Docker
      ansible.builtin.yum:
        name:
          - libselinux-python
          - docker
          - gh
        state: latest
        update_cache: yes

    - name: Configure Docker
      ansible.builtin.shell: |
        service docker start
        systemctl enable docker
        usermod -a -G docker ec2-user
        chmod 777 /var/run/docker.sock
      ignore_errors: yes

    - name: Create .aws directory if it does not exist
      ansible.builtin.file:
        path: /home/ec2-user/.aws
        state: directory
        mode: '0775'

    - name: Create Aws Config
      ansible.builtin.copy:
        dest: "{{ aws_conf }}"
        content: |
          [default]
          region = $region
          output = json
        mode: '600'
        owner: ec2-user
        group: ec2-user

    - name: Create Aws Creds
      ansible.builtin.copy:
        dest: "{{ aws_creds }}"
        content: |
          [default]
          AWS_ACCESS_KEY_ID=XXXXXXX_NOT_EXPOSED_XXXXXXX
          AWS_SECRET_ACCESS_KEY=XXXXXXX_NOT_EXPOSED_XXXXXXX
        mode: '0600'
        owner: ec2-user
        group: ec2-user

    - name: Add IP to loopback
      ansible.builtin.shell: |
        ip a a 172.31.80.80 dev lo
        route add -host 172.31.80.80 dev lo
        echo "---------------"
        echo "IP added"
      register: ip
      async: 10
      poll: 2

    - name: Debug IP
      ansible.builtin.debug:
        var: ip

    - name: Extract jenkins_home into /var/lib/docker/volumes
      ansible.builtin.unarchive:
        src: /home/a/jenkins_home.zip
        dest: /var/lib/docker/volumes

    - name: Docker / Jenkins start
      ansible.builtin.shell:
        docker run -d -v jenkins_home:/var/jenkins_home \\
           -p 8080:8080 --restart=on-failure jenkins/jenkins:lts-jdk11
      async: 120
      poll: 10

    - name: Recursively change ownership of _data
      ansible.builtin.file:
        path: /var/lib/docker/volumes/jenkins_home/_data
        state: directory
        recurse: yes
        owner: ec2-user
        group: ec2-user

    - name: Create Jenkins test file
      ansible.builtin.copy:
        dest: "{{ dest }}"
        content: |
          #!/bin/bash
          #
          retry() {
          function="\$@"
          count=0
          max=100
          sleep=2
          #
          while :; do
          \$function && break
          if [ \$count -lt \$max ]; then
          ((count++))
          echo "Command failed, retrying after \$sleep seconds... \$count/\$max"
          sleep \$sleep
          continue
          fi
          echo "Command failed, out of retries." && exit 1
          done
          }
          #
          healthcheck() {
          curl -Ls \$1 | grep "Authentication required" >/dev/null 2>&1
          [ \$? -ne 0 ] && echo "Jenkins hasn't responded" && return 1
          echo "Jenkins is up"
          }
          #
          [ \$# -ne 1 ] && echo "1 argument required, got \$#" && exit 1
          retry healthcheck \$1
        mode: '0777'
      register: testfile

    - name: Jenkins test if it is up
      ansible.builtin.shell:
        ./jcheck.sh localhost:8080
      register: jtest
      async: 100
      poll: 10

    - name: Jenkins test if it is up
      ansible.builtin.debug:
        var: jtest

    - name: Create GH Token file
      ansible.builtin.copy:
        dest: "{{ dest_token }}"
        content: 'ghp_XXXXXXX_NOT_EXPOSED_XXXXXXX'
        owner: ec2-user
        group: ec2-user
        mode: '600'

    - name: GH CLI Auth
      become_user: ec2-user
      ansible.builtin.shell:
        gh auth login --with-token <~/.ssh/token
      register: auth
      async: 10
      poll: 2

    - name: Debug GH Auth
      ansible.builtin.debug:
        var: auth

    - name: Install cli/gh-webhook
      become_user: ec2-user
      ansible.builtin.shell:
          gh extension install cli/gh-webhook
      register: install_ghwh
      async: 10
      poll: 2

    - name: Debug GH Webhook Install
      ansible.builtin.debug:
        var: install_ghwh

    - name: Set GitHub Webhook
      become_user: ec2-user
      ansible.builtin.shell: |
        gh webhook forward --repo HarrierPanels/sql \\
          --events=push --url="http://localhost:8080/github-webhook/"
        echo 'Webhook set!'
      async: 45
      poll: 0

    - name: Git push at localhost
      become_user: a
      ansible.builtin.shell: |
        cd /home/a/sql
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
cat <<EOF >"$iac_dir"/ansible.cfg
[defaults]
host_key_checking    = false
inventory            = $filename.txt
deprecation_warnings = False
EOF

cat <<EOF >"$iac_dir"/"$filename".txt 
[$filename]
$public_ip

[local]
localhost ansible_host=localhost
EOF

cat <<EOF >"$iac_dir"/group_vars/"$filename" 
---
ansible_user: ec2-user
ansible_ssh_private_key_file: ~/.ssh/XXXXXXX_NOT_EXPOSED_XXXXXXX.pem
EOF

cat <<EOF >"$iac_dir"/group_vars/local 
---
ansible_user: a
ansible_ssh_private_key_file: ~/.ssh/XXXXXXX_NOT_EXPOSED_XXXXXXX.pem
EOF

playbook
}

# (Optional) Production Live Server start
start_prod() {
/usr/local/bin/aws ec2 start-instances \
                --instance-ids $prod_live_id
}

# (Optional) Production Live Server stop
stop_prod() {
sleep 240 &&
/usr/local/bin/aws ec2 stop-instances \
                --instance-ids $prod_live_id               
} 

# Crontab / Terraform / Ansible / Jenkins CI/CD
cicd_toolchain() {
mkdir -p "$iac_dir"/group_vars && trf_setup &&
## Optional ##
start_prod &&
############## 
terraform -chdir="$iac_dir" init &&
terraform -chdir="$iac_dir" apply -auto-approve
init && retry awscheck $url && ec2_info
echo "Configuring..."
ans_setup && sleep 5 && statuscheck
ansible-playbook "$iac_dir"/*yml -i "$iac_dir"/*txt \
   --ssh-common-args='-o StrictHostKeyChecking=no' -b -vvv
retry awscheck $url && ec2_info && statecheck
## Optional ##
stop_prod
##############  
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
