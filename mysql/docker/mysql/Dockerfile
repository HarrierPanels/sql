# Create MySQL Image
FROM mysql:latest
MAINTAINER HarrierPanels 

ENV MYSQL_ROOT_PASSWORD 7Ujm8ik,9ol.
ENV MYSQL_USER a
ENV MYSQL_DATABASE cms_db 
ENV MYSQL_PASSWORD 7Ujm8ik,9ol.

ADD /bkp/*.gz /docker-entrypoint-initdb.d
COPY /bkp/.my.cnf /root/

EXPOSE 3306
