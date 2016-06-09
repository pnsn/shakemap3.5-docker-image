# Create a docker image to use for ShakeMap at the PNSN
FROM centos:7
MAINTAINER Renate Hartog <jrhartog@uw.edu>
#
# install Oracle instant client from local files
COPY /oracle/oracle-instantclient-*-10.2.0.5-1.x86_64.rpm /
# 
RUN rpm -i oracle-instantclient-basic-10.2.0.5-1.x86_64.rpm \
           oracle-instantclient-devel-10.2.0.5-1.x86_64.rpm \
           oracle-instantclient-sqlplus-10.2.0.5-1.x86_64.rpm \
           && rm /oracle-instantclient-basic-10.2.0.5-1.x86_64.rpm \
           && rm /oracle-instantclient-devel-10.2.0.5-1.x86_64.rpm \
           && rm /oracle-instantclient-sqlplus-10.2.0.5-1.x86_64.rpm


# add EPEL repo and install all required packages for GMT
RUN yum -y update && yum -y install epel-release && yum -y update && yum -y install \
    expat-devel \
    expect \
    gcc \
    java-1.7.0-openjdk \
    make \
    subversion \
    which \
    openssh-clients \
    rsync \
    netcdf \
    netcdf-devel \
    gshhg-gmt-nc4-full \
    dcw-gmt \
    ghostscript \
    GraphicsMagick \
    perl-libwww-perl \
    perl-DBD-mysql \
    perl-HTML-Template \
    perl-XML-Parser \
    perl-XML-Writer \
    perl-enum \
    perl-Event \
    perl-Mail-Sender \
    perl-Config-General \
    perl-XML-Simple \
    perl-DateTime \
    perl-ExtUtils-MakeMaker \
    perl-JSON-PP \
    mariadb \
    zip \
    python

# Install GMT 4.5 from local files (epel only provides GMT 5+)
ADD *.tar.* /

# environment variables, needed to build things etc.
ENV GMTDIR=/gmt-4.5.14 \
    SRCDIR=/home/shake/ShakeMap \
    SHAKE_HOME=/home/shake \
    GMT_VERSION=4.5 \
    ORACLE_HOME=/usr/lib/oracle/10.2.0.5/client64 \
    LD_LIBRARY_PATH=/gmt-4.5.14/lib:/usr/lib/oracle/10.2.0.5/client64/lib

# build and install GMT 4.5
WORKDIR gmt-4.5.14
RUN ./configure --datadir=/usr/share/gmt --with-gshhg-dir=/usr/share/gshhg-gmt-nc4 --disable-mex --disable-xgrid --enable-shared --bindir=/usr/local/bin \
    && make && make install-gmt && make install-data && make clean

# build and install DBD::Oracle, Time-modules, and Math::CDF
WORKDIR /DBD-Oracle-1.75_2
RUN perl Makefile.PL && make && make install
#
WORKDIR /Time-modules-2013.0912
RUN perl Makefile.PL && make && make install
#
WORKDIR /Math-CDF-0.1
RUN perl Makefile.PL && make && make install


# scripts to get around expired ShakeMap certificate, paths, etc.
# also include docker-entrypoint.sh
COPY /scripts/* /usr/bin/

# checkout latest version of shakemap, configure, build, install
RUN mkdir -p /home/shake/data \
    && mkdir /home/shake/config \
    && mkdir /home/shake/lib \
    && mkdir /home/shake/logs \
    && mkdir /home/shake/pw \
    && mkdir /home/shake/ProductClient \
    && /usr/bin/accept_expired_cert \
    && svn checkout -q https://vault.gps.caltech.edu/repos/products/shakemap/tags/release-3.5/ ${SRCDIR} 
#
WORKDIR ${SRCDIR}/install
RUN make && change_macros_file ${SRCDIR}/include/macros

WORKDIR ${SRCDIR}
RUN make all && make mp && make web && make pyprogs && ln -s ${SRCDIR}/bin ${SRCDIR}/../bin && change_ShakeConfig lib/ShakeConfig.pm
COPY /dam_calc_1.3.pl /home/shake/ShakeMap/bin
#replace the ShakeMap transfer with mine so that you can specify a path to ssh_privatekey
COPY /transfer /home/shake/ShakeMap/bin
#replace the getdyfi2 with mine to get around wrong URL and relative paths
COPY /getdyfi2 /home/shake/ShakeMap/bin

ENV PATH ${SRCDIR}/bin:${PATH}
    
# volumes for output (data), configuration files (config)
# and local data such as Vs30 grids (lib)
# mount to host directories to have easy to find 
# persistent data
VOLUME /home/shake/data \
       /home/shake/config \
       /home/shake/lib \
       /home/shake/logs \
       /home/shake/pw \
       /home/shake/ProductClient
# expose the queue port
EXPOSE 2345
# exec 'queue' if container is started without arguments
# or "exec arguments" if it is started with.
ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
