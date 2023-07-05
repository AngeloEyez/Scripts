#!/bin/bash

# ##########################################################
#
# This script installs Authelia with
# a template configuration like it is
# outlined in this video:
#
# a detailed description is also available
# on https://www.onemarcfifty.com/blog/Authelia_Proxmox/
#
# ##########################################################

# The script needs to be run as root!

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# ####################################
# ##### first we update apt 
# ##### and apt sources, 
# ##### then we install authelia
# ####################################

apt update
apt install -y curl gnupg apt-transport-https sudo
curl -s https://apt.authelia.com/organization/signing.asc | sudo apt-key add -
echo "deb https://apt.authelia.com/stable/debian/debian/ all main" >>/etc/apt/sources.list.d/authelia.list
apt-key export C8E4D80D | sudo gpg --dearmour -o /usr/share/keyrings/authelia.gpg
apt update
apt install -y authelia

# ####################################
# ##### Now we create the secrets 
# ##### and the systemd unit file
# ####################################

for i in .secrets .users .assets .db ; do mkdir /etc/authelia/$i ; done
for i in jwtsecret session storage smtp oidcsecret redis ; do tr -cd '[:alnum:]' < /dev/urandom | fold -w "64" | head -n 1 | tr -d '\n' > /etc/authelia/.secrets/$i ; done
openssl genrsa -out /etc/authelia/.secrets/oicd.pem 4096
openssl rsa -in /etc/authelia/.secrets/oicd.pem -outform PEM -pubout -out /etc/authelia/.secrets/oicd.pub.pem
(cat >/etc/authelia/secrets) <<EOF
AUTHELIA_JWT_SECRET_FILE=/etc/authelia/.secrets/jwtsecret
AUTHELIA_SESSION_SECRET_FILE=/etc/authelia/.secrets/session
AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE=/etc/authelia/.secrets/storage
AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE=/etc/authelia/.secrets/smtp
AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE=/etc/authelia/.secrets/oidcsecret
AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE=/etc/authelia/.secrets/oicd.pem
EOF
chmod 600 -R /etc/authelia/.secrets/
chmod 600 /etc/authelia/secrets
(cat >/etc/systemd/system/authelia.service) <<EOF
[Unit]
Description=Authelia authentication and authorization server
After=multi-user.target

[Service]
Environment=AUTHELIA_SERVER_DISABLE_HEALTHCHECK=true
EnvironmentFile=/etc/authelia/secrets
ExecStart=/usr/bin/authelia --config /etc/authelia/configuration.yml
SyslogIdentifier=authelia

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# ####################################
# ##### Now we create a user yaml
# ##### file and then ask for new user
# ##### 
# ####################################

echo "users:" > /etc/authelia/.users/users_database.yml
while true; do
  echo -e "Create user\nUser name (\"N\" to skip):"
  read -r user

  if [[ $user == "N" ]]; then
    break
  fi

  echo "Password:"
  read -r pass

  echo "Display Name:"
  read -r displayname

  echo "Email:"
  read -r email

  encryptedpwd=$(authelia hash-password --no-confirm -- "$pass" | cut -d " " -f 2)

  {
    echo "  ${user}:"
    echo "    displayname: \"$displayname\""
    echo "    password: $encryptedpwd"
    echo "    email: $email"
  } >> /etc/authelia/.users/users_database.yml

  echo "User '$user' created."
done
chmod 600 -R /etc/authelia/.users/

# ####################################
# ##### Next, we pull the skeleton of
# ##### the authelia config file from
# ##### Marc's Github Repo
# ####################################

cd /etc/authelia
# save the old version of the file
if [ -e configuration.yml ] ; then
  mv configuration.yml configuration.yml.old
fi
# Now let's use Marc's version of Florian's Template File for the new config:
wget https://raw.githubusercontent.com/onemarcfifty/cheat-sheets/main/templates/authelia/configuration.yml
chmod 600 configuration.yml

# ##### Now let's try and start Authelia

systemctl enable authelia
systemctl start authelia
