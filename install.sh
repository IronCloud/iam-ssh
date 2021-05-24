#!/bin/bash -e

#Forked from https://github.com/widdix/aws-ec2-ssh

show_help() {
cat << EOF
Usage: ${0##*/} [-hv] [-a ARN] [-i GROUP,GROUP,...] [-l GROUP,GROUP,...] [-s GROUP] [-x REGION] [-p PROGRAM] [-u "ARGUMENTS"] [-r RELEASE]
Install import_users.sh and authorized_key_commands.

    -h                 display this help and exit
    -v                 verbose mode.

    -a arn             Assume a role before contacting AWS IAM to get users and keys.
                       This can be used if you define your users in one AWS account, while the EC2
                       instance you use this script runs in another.
    -i group,group     Which IAM groups have access to this instance
                       Comma seperated list of IAM groups. Leave empty for all available IAM users
    -l group,group     Give the users these local UNIX groups
                       Comma seperated list
    -s group,group     Specify IAM group(s) for users who should be given sudo privileges, or leave
                       empty to not change sudo access, or give it the value '##ALL##' to have all
                       users be given sudo rights.
                       Comma seperated list
    -p program         Specify your useradd program to use.
                       Defaults to '/usr/sbin/useradd'
    -x region          Specify your AWS govcloud region.
                       Defaults to us-gov-east-1
    -u "useradd args"  Specify arguments to use with useradd.
                       Defaults to '--create-home --shell /bin/bash'
    -r release         Specify a release of aws-ec2-ssh to download from GitHub. This argument is
                       passed to \`git clone -b\` and so works with branches and tags.
                       Defaults to 'master'


EOF
}

export SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
export AUTHORIZED_KEYS_COMMAND_FILE="/etc/authorized_keys_command.sh"
export IMPORT_USERS_SCRIPT_FILE="/etc/import_users.sh"
export MAIN_CONFIG_FILE="/etc/aws-ec2-ssh.conf"

IAM_GROUPS=""
SUDO_GROUPS=""
LOCAL_GROUPS=""
ASSUME_ROLE=""
USERADD_PROGRAM=""
USERADD_ARGS=""
USERDEL_PROGRAM=""
USERDEL_ARGS=""
AWS_REGION="us-gov-east-1"
RELEASE="master"
AuthorizedKeysCommandUser="iamawsssh"

while getopts :hva:i:l:s:p:u:d:x:f:r: opt
do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        i)
            IAM_GROUPS="$OPTARG"
            ;;
        s)
            SUDO_GROUPS="$OPTARG"
            ;;
        l)
            LOCAL_GROUPS="$OPTARG"
            ;;
        x)
            AWS_REGION="$OPTARG"
            ;;
        v)
            set -x
            ;;
        a)
            ASSUME_ROLE="$OPTARG"
            ;;
        p)
            USERADD_PROGRAM="$OPTARG"
            ;;
        u)
            USERADD_ARGS="$OPTARG"
            ;;
        d)
            USERDEL_PROGRAM="$OPTARG"
            ;;
        f)
            USERDEL_ARGS="$OPTARG"
            ;;
        r)
            RELEASE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            show_help
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            show_help
            exit 1
    esac
done

export IAM_GROUPS
export SUDO_GROUPS
export LOCAL_GROUPS
export ASSUME_ROLE
export USERADD_PROGRAM
export USERADD_ARGS
export USERDEL_PROGRAM
export USERDEL_ARGS
export AWS_REGION



# Add AWS CLI and remove ec2 instance connect
apt update && apt install awscli -y 
apt remove ec2-instance-connect -y 

# Add system user for AuthorizedKeysCommandUser
/usr/sbin/addgroup $AuthorizedKeysCommandUser ; /usr/sbin/adduser --system $AuthorizedKeysCommandUser --shell /bin/bash --quiet --disabled-password ; /usr/sbin/adduser $AuthorizedKeysCommandUser $AuthorizedKeysCommandUser

# check if iamsshuser exists
if getent passwd iamawsssh > /dev/null 2>&1; then
    sleep 1
else
    echo "the AuthorizedKeysCommandUser user does not exist, exiting!"
    exit 1
fi

# check if AWS CLI exists
if ! [ -x "$(which aws)" ]; then
    echo "aws executable not found - exiting!"
    exit 1
fi

# check if git exists
if ! [ -x "$(which git)" ]; then
    echo "git executable not found - exiting!"
    exit 1
fi



tmpdir=$(mktemp -d)

cd "$tmpdir"

# Clone the GovCloud repo
git clone https://github.com/IronCloud/iam-ssh.git

cd "$tmpdir/iam-ssh"

cp authorized_keys_command.sh $AUTHORIZED_KEYS_COMMAND_FILE
cp import_users.sh $IMPORT_USERS_SCRIPT_FILE


#CHANGE SCRIPT PERMISSIONS! Gotcha
/usr/bin/chgrp iamawsssh $AUTHORIZED_KEYS_COMMAND_FILE
/usr/bin/chmod 755 $AUTHORIZED_KEYS_COMMAND_FILE

if [ "${IAM_GROUPS}" != "" ]
then
    echo "IAM_AUTHORIZED_GROUPS=\"${IAM_GROUPS}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${AWS_REGION}" != "" ]
then
    echo "AWS_REGION=\"${AWS_REGION}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${SUDO_GROUPS}" != "" ]
then
    echo "SUDOERS_GROUPS=\"${SUDO_GROUPS}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${LOCAL_GROUPS}" != "" ]
then
    echo "LOCAL_GROUPS=\"${LOCAL_GROUPS}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${ASSUME_ROLE}" != "" ]
then
    echo "ASSUMEROLE=\"${ASSUME_ROLE}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${USERADD_PROGRAM}" != "" ]
then
    echo "USERADD_PROGRAM=\"${USERADD_PROGRAM}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${USERADD_ARGS}" != "" ]
then
    echo "USERADD_ARGS=\"${USERADD_ARGS}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${USERDEL_PROGRAM}" != "" ]
then
    echo "USERDEL_PROGRAM=\"${USERDEL_PROGRAM}\"" >> $MAIN_CONFIG_FILE
fi

if [ "${USERDEL_ARGS}" != "" ]
then
    echo "USERDEL_ARGS=\"${USERDEL_ARGS}\"" >> $MAIN_CONFIG_FILE
fi

#./install_configure_selinux.sh

./install_configure_sshd.sh

cat > /etc/cron.d/import_users << EOF
SHELL=/bin/bash
PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/aws/bin
MAILTO=root
HOME=/
*/2 * * * * root $IMPORT_USERS_SCRIPT_FILE
EOF
chmod 0644 /etc/cron.d/import_users

$IMPORT_USERS_SCRIPT_FILE

./install_restart_sshd.sh

# change permissions of /etc/aws-ec2-ssh.conf to fix bug after hardening
/usr/bin/chgrp iamawsssh /etc/aws-ec2-ssh.conf
/usr/bin/chmod 755 /etc/aws-ec2-ssh.conf
