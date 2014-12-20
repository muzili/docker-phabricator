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
  bin/config set mysql.host $MYSQL_PORT_3306_TCP_ADDR
  bin/config set mysql.port $MYSQL_PORT_3306_TCP_PORT
  bin/config set mysql.user $MYSQL_ENV_USER
  bin/config set mysql.pass $MYSQL_ENV_PASS
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
