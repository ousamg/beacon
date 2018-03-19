# Dockerfile for Beacon
FROM python:2.7
#=====================#
# Setup Prerequisites #
#=====================#
RUN apt-get update && apt-get install -y --no-install-recommends apache2 vim sqlite3 bedtools \
	&& a2enmod cgi \
	&& service apache2 restart \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get clean

#===============================#
# Docker Image Configuration	#
#===============================#
LABEL Description='GA4GH Beacon' \
		Vendor='Oslo Universityssykehus - Avdeling for medisinsk genetikk' \
		Maintainer='tor.solli-nowlan@medisin.uio.no'

#=====================#
# Install Beacon 	  #
#=====================#
ENV BEACON_DIR=/var/www/html/beacon
COPY . $BEACON_DIR
WORKDIR $BEACON_DIR
RUN pip install -r requirements.txt

#=====================#
# Configure Beacon 	  #
#=====================#
RUN echo "ServerName localhost" | tee /etc/apache2/conf-available/fqdn.conf \
	&& a2enconf fqdn
COPY config/beacon.conf ${BEACON_DIR}/${REPO_NAME}/beacon.conf
COPY config/apache2.conf /etc/apache2/apache2.conf

#=====================#
# Beacon Startup 	  #
#=====================#
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
