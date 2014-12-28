pre_start_action() {
  mkdir -p $DATA_DIR
  mkdir -p $LOG_DIR/nginx
  mkdir -p $LOG_DIR/php-fpm
  mkdir -p $LOG_DIR/supervisor
  mkdir -p $REPO_DIR

  # Add users
  echo "git:x:2000:2000:user for phabricator ssh:/srv/www/phabricator/phabricator:/bin/bash" >> /etc/passwd
  echo "phab-daemon:x:2001:2000:user for phabricator daemons:/srv/www/phabricator/phabricator:/bin/bash" >> /etc/passwd
  echo "wwwgrp-phabricator:!:2000:nginx" >> /etc/group
  echo "git ALL=(phab-daemon) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack" > /etc/sudoers.d/git
  echo "git ALL=(phab-daemon) SETENV: NOPASSWD: /usr/bin/git-http-backend, /usr/bin/hg" >/etc/sudoers.d/www
  echo "nginx ALL=(phab-daemon) SETENV: NOPASSWD: /usr/bin/git-http-backend, /usr/bin/hg" >>/etc/sudoers.d/www
  sed -i -e's/\(Defaults \+requiretty\)/#\1/g' /etc/sudoers
  ln -sf /usr/libexec/git-core/git-http-backend /usr/bin/git-http-backend

  mkdir -p /etc/phabricator-ssh
  cat > /etc/phabricator-ssh/sshd_config <<EOF
  AuthorizedKeysCommand /scripts/phabricator-ssh-hook.sh
  AuthorizedKeysCommandUser git
  AllowUsers git

  # You may need to tweak these options, but mostly they just turn off everything
  # dangerous.

  Port 10022
  Protocol 2
  PermitRootLogin no
  AllowAgentForwarding no
  AllowTcpForwarding no
  PrintMotd no
  PrintLastLog no
  PasswordAuthentication no
  AuthorizedKeysFile none

  PidFile /run/sshd-phabricator.pid

EOF
  chown root:root /etc/phabricator-ssh/

#  mkdir -p /run/php-fpm
#  chown git:wwwgrp-phabricator /run/php-fpm
  cat > /etc/php-fpm.conf <<EOF
[global]
pid = /run/php-fpm/php-fpm.pid
error_log = /var/log/php-fpm/error.log
daemonize = no
[www]
user = git
group = wwwgrp-phabricator
listen = /var/run/php-fpm/www.sock
listen.owner = git
listen.group = wwwgrp-phabricator
listen.mode = 0666
pm = dynamic
pm.max_children = 4
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 4
catch_workers_output = yes
php_admin_value[error_log] = /var/log/php-fpm/phabricator.php.log

EOF
  cd $DATA_DIR

  if [ ! -d libphutil ]; then
    echo "Cloning libphutil..."
    git clone https://github.com/phacility/libphutil.git
  else
    echo "The directory of libphutil is not empty. Left as is."
  fi

  if [ ! -d arcanist ]; then
    echo "Cloning Arcanist..."
    git clone https://github.com/phacility/arcanist.git
  else
    echo "The directory of Arcanist is not empty. Left as is."
  fi

  if [ ! -d phabricator ]; then
    echo "Cloning Phabricator..."
    git clone https://github.com/phacility/phabricator.git
  else
    echo "The directory of Phabricator is not empty. Left as is."
  fi

  # Set up the Phabricator code base
  chown git:wwwgrp-phabricator $DATA_DIR

  cd phabricator
  echo "mysql: $MYSQL_ENV_USER:$MYSQL_ENV_PASS@$MYSQL_PORT_3306_TCP_ADDR:$MYSQL_PORT_3306_TCP_PORT"
  RET=1
  TIMEOUT=0
  while [[ RET -ne 0 ]]; do
      echo "=> Waiting for confirmation of MariaDB service startup"
      sleep 5
      echo "Add 5 seconds to timeout"
      ((TIMEOUT+=5))
      echo "check current timeout value:$TIMEOUT"
      if [[ $TIMEOUT -gt 60 ]]; then
          echo "Failed to connect mariadb"
          exit 1
      fi
      echo "check mysql status"
      mysql -u$MYSQL_ENV_USER -p$MYSQL_ENV_PASS \
            -h$MYSQL_PORT_3306_TCP_ADDR \
            -P$MYSQL_PORT_3306_TCP_PORT \
            -e "status"
      RET=$?
      echo "mysql status is $RET"
  done

  echo "Connected mariadb"
  bin/config set mysql.host $MYSQL_PORT_3306_TCP_ADDR
  bin/config set mysql.port $MYSQL_PORT_3306_TCP_PORT
  bin/config set mysql.user $MYSQL_ENV_USER
  bin/config set mysql.pass $MYSQL_ENV_PASS

  # Set the base url to virtual host
  bin/config set phabricator.base-uri "http://$VIRTUAL_HOST/"
  bin/config set phd.user phab-daemon
  bin/config set diffusion.ssh-user git
  bin/config set diffusion.ssh-port 10022
  bin/config set diffusion.allow-http-auth true

  # Set the auth option
  bin/config set auth.require-email-verification true
  if [[ ! -z "$PERMIT_DOMAINS" ]]; then
      bin/config set auth.email-domains "$PERMIT_DOMAINS"
  fi

  # Set the smtp host
  if [[ ! -z "$SMTP_HOST" ]]; then
      bin/config set metamta.mail-adapter "PhabricatorMailImplementationPHPMailerAdapter"
      bin/config set phpmailer.mailer "smtp"
      bin/config set phpmailer.smtp-host "$SMTP_HOST"
      bin/config set phpmailer.smtp-port $SMTP_PORT
      bin/config set phpmailer.smtp-user "$SMTP_USER"
      bin/config set phpmailer.smtp-password "$SMTP_PASS"
      bin/config set phpmailer.smtp-protocol "tls"
  fi

  bin/config set phabricator.timezone "Asia/Shanghai"
  sed -i -e"s/phabricator.local/$VIRTUAL_HOST/g" /etc/nginx/sites-available/phabricator.conf
  bin/config set storage.upload-size-limit 100M
  bin/storage upgrade --force

  mkdir -p /etc/supervisor/conf.d
  cat > /etc/supervisord.conf <<-EOF
[unix_http_server]
file=/run/supervisor.sock   ; (the path to the socket file)

[supervisord]
logfile=/var/log/supervisor/supervisord.log ; (main log file;default $CWD/supervisord.log)
logfile_maxbytes=50MB       ; (max main logfile bytes b4 rotation;default 50MB)
logfile_backups=10          ; (num of main logfile rotation backups;default 10)
loglevel=info               ; (log level;default info; others: debug,warn,trace)
pidfile=/run/supervisord.pid ; (supervisord pidfile;default supervisord.pid)
nodaemon=true               ; (start in foreground if true;default false)
minfds=1024                 ; (min. avail startup file descriptors;default 1024)
minprocs=200                ; (min. avail process descriptors;default 200)

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisor.sock ; use a unix:// URL  for a unix socket

[include]
files = /etc/supervisor/conf.d/*.conf
EOF
  cat > /etc/supervisor/conf.d/phab.conf <<-EOF
[program:php5-fpm]
command=/usr/sbin/php-fpm --nodaemonize

[program:nginx]
command=/usr/sbin/nginx

[program:PhabricatorRepositoryPullLocalDaemon]
user=phab-daemon
command=/srv/www/phabricator/phabricator/scripts/daemon/phd-daemon PhabricatorRepositoryPullLocalDaemon --phd=/var/tmp/phd/pid
stdout_logfile=/var/log/supervisor/PhabricatorRepositoryPullLocalDaemon.log
stderr_logfile=/var/log/supervisor/PhabricatorRepositoryPullLocalDaemon_err.log

[program:PhabricatorGarbageCollectorDaemon]
user=phab-daemon
command=/srv/www/phabricator/phabricator/scripts/daemon/phd-daemon PhabricatorGarbageCollectorDaemon --phd=/var/tmp/phd/pid
stdout_logfile=/var/log/supervisor/PhabricatorGarbageCollectorDaemon.log
stderr_logfile=/var/log/supervisor/PhabricatorGarbageCollectorDaemon_err.log

[program:PhabricatorTaskmasterDaemon1]
user=phab-daemon
command=/srv/www/phabricator/phabricator/scripts/daemon/phd-daemon PhabricatorTaskmasterDaemon --phd=/var/tmp/phd/pid
stdout_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon1.log
stderr_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon1_err.log

[program:PhabricatorTaskmasterDaemon2]
user=phab-daemon
command=/srv/www/phabricator/phabricator/scripts/daemon/phd-daemon PhabricatorTaskmasterDaemon --phd=/var/tmp/phd/pid
stdout_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon2.log
stderr_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon2_err.log

[program:PhabricatorTaskmasterDaemon3]
user=phab-daemon
command=/srv/www/phabricator/phabricator/scripts/daemon/phd-daemon PhabricatorTaskmasterDaemon --phd=/var/tmp/phd/pid
stdout_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon3.log
stderr_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon3_err.log

[program:PhabricatorTaskmasterDaemon4]
user=phab-daemon
command=/srv/www/phabricator/phabricator/scripts/daemon/phd-daemon PhabricatorTaskmasterDaemon --phd=/var/tmp/phd/pid
stdout_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon4.log
stderr_logfile=/var/log/supervisor/PhabricatorTaskmasterDaemon4_err.log

[group:phd]
programs=PhabricatorRepositoryPullLocalDaemon,PhabricatorGarbageCollectorDaemon,PhabricatorTaskmasterDaemon1,PhabricatorTaskmasterDaemon2,PhabricatorTaskmasterDaemon3,PhabricatorTaskmasterDaemon4

[program:cron]
command=crond -n

[program:phab-sshd]
command=/usr/sbin/sshd -D -f /etc/phabricator-ssh/sshd_config

EOF

  mkdir -p /var/tmp/phd/pid
  chmod 0777 /var/tmp/phd/pid
  chown -R phab-daemon:2000 $REPO_DIR
  chown -R git:wwwgrp-phabricator $DATA_DIR
  chown -R nginx:nginx "$LOG_DIR/nginx"
}

post_start_action() {
  rm /first_run
}
