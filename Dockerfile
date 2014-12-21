FROM muzili/centos-php

MAINTAINER Joshua Lee <muzili@gmail.com>

# Install git to download Phabricator.
RUN yum -y install git mysql pcre-devel php-pear && \
    pecl install apc && \
    yum clean all

# Download Phabricator bundle.
RUN mkdir -p /srv/www/phabricator

# Create a directory for the source code.
RUN mkdir -p /srv/git/

RUN rm -rf /etc/nginx/sites-enabled/default.conf
ADD etc/phabricator.conf /etc/nginx/sites-available/phabricator.conf
RUN ln -s /etc/nginx/sites-available/phabricator.conf /etc/nginx/sites-enabled

ADD scripts /scripts
RUN chmod +x /scripts/start.sh
RUN touch /first_run

# Expose our web root and log directories log.
VOLUME ["/srv/www/phabricator", "/srv/git", "/var/log"]

# Expose the port
EXPOSE 80 443

# Kicking in
CMD ["/scripts/start.sh"]

