#!/bin/bash

set -x

echo "Upgrading Phabricator..."

pushd /srv/www/phabricator/phabricator/libphutil
git pull --rebase
popd

pushd /srv/www/phabricator/phabricator/arcanist
git pull --rebase
popd

pushd /srv/www/phabricator/phabricator/phabricator
git pull --rebase
popd

echo "Applying any pending DB schema upgrades..."
/srv/www/phabricator/phabricator/phabricator/bin/storage upgrade --force

echo "Restarting nginx"
supervisorctl restart nginx

# Check to make sure the notification services are running
echo "Restarting aphlict"
/srv/www/phabricator/phabricator/phabricator/bin/aphlict restart

# Restarts the processes belonging to the group "phd"
echo "Restarting phd daemons"
supervisorctl restart phd:
