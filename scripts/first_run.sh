pre_start_action() {
  mkdir -p $DATA_DIR
  mkdir -p $LOG_DIR/nginx
  mkdir -p $LOG_DIR/php-fpm

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
  sed -i -e"s/phabricator.local/$VIRTUAL_HOST/g" /etc/nginx/sites-available/phabricator.conf
  bin/storage upgrade --force
  bin/phd start

  mkdir -p /etc/supervisor/conf.d
  cat > /etc/supervisor/conf.d/supervisord.conf <<-EOF
[supervisord]
nodaemon=true

[program:php5-fpm]
command=/usr/sbin/php-fpm --nodaemonize

[program:nginx]
command=/usr/sbin/nginx

EOF

  chown -R nginx:nginx $DATA_DIR
  chown -R nginx:nginx "$LOG_DIR/nginx"
}

post_start_action() {
  rm /first_run
}
