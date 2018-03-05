# Dockerfile for Beacon
FROM python:2.7
#=====================#
# Setup Prerequisites #
#=====================#
RUN apt-get update && apt-get install -y apache2 vim \
	&& a2enmod cgi \
	&& service apache2 restart \
	&& rm -rf /var/lib/apt/lists/*
#===============================#
# Docker Image Configuration	#
#===============================#
LABEL Description='Beacon' \
		Vendor='Oslo Universityssykehus - Avdeling for medisinsk genetikk' \
		maintainer='tsnowlan@gmail.com'
#=====================#
# Install Beacon 	  #
#=====================#
ENV BEACON_DIR=/var/www/html/beacon REPO_NAME=ousBeacon REPO_URL=https://github.com/tsnowlan/ousBeacon.git
WORKDIR ${BEACON_DIR}
RUN git clone ${REPO_URL} \
	&& cd ${REPO_NAME}/ \
	&& sed -i "s/'server.socket_port': port/'server.socket_port': port, 'server.socket_host': '0.0.0.0'/g" query
#=====================#
# Configure Beacon 	  #
#=====================#
RUN echo "ServerName localhost" | tee /etc/apache2/conf-available/fqdn.conf \
	&& a2enconf fqdn
COPY config/beacon.conf ${BEACON_DIR}/${REPO_NAME}/beacon.conf
COPY config/apache2.conf /etc/apache2/apache2.conf
# COPY app ${BEACON_DIR}
#=====================#
# Beacon Startup 	  #
#=====================#
CMD /usr/sbin/apache2ctl -D FOREGROUND
