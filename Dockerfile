# Multi-stage build for FusionPBX
# Stage 1: Build dependencies and FreeSWITCH
FROM debian:12 AS builder

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    build-essential \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libdb-dev \
    unixodbc-dev \
    libncurses5-dev \
    libexpat1-dev \
    libgdbm-dev \
    bison \
    erlang-dev \
    libtpl-dev \
    libtiff-dev \
    uuid-dev \
    libpcre3-dev \
    libedit-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    nasm \
    yasm \
    libogg-dev \
    libvorbis-dev \
    libflac-dev \
    libopus-dev \
    libspeex-dev \
    libspeexdsp-dev \
    libldns-dev \
    python3-dev \
    liblua5.3-dev \
    libavformat-dev \
    libswscale-dev \
    libswresample-dev \
    libjpeg-dev \
    libpng-dev \
    libfreetype6-dev \
    valgrind \
    # FreeSWITCH specific dependencies
    libpq-dev \
    libmariadb-dev \
    uuid-dev \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Build dependencies for FreeSWITCH 1.10+
WORKDIR /usr/src

# libks (required for FreeSWITCH 1.10+)
RUN git clone https://github.com/signalwire/libks.git libks \
    && cd libks \
    && cmake . \
    && make -j $(nproc) \
    && make install

# Sofia-SIP
RUN wget https://github.com/freeswitch/sofia-sip/archive/refs/tags/v1.13.17.zip \
    && unzip v1.13.17.zip \
    && cd sofia-sip-1.13.17 \
    && sh autogen.sh \
    && ./configure --enable-debug \
    && make -j $(nproc) \
    && make install

# SpanDSP (build from source for FreeSWITCH compatibility)
RUN git clone https://github.com/freeswitch/spandsp.git spandsp \
    && cd spandsp \
    && git reset --hard 0d2e6ac65e0e8f53d652665a743015a88bf048d4 \
    && sh autogen.sh \
    && ./configure --enable-debug \
    && make -j $(nproc) \
    && make install \
    && ldconfig

# Download and compile FreeSWITCH
RUN git clone -b v1.10.12 --depth 1 https://github.com/signalwire/freeswitch.git /usr/src/freeswitch
WORKDIR /usr/src/freeswitch

# Configure FreeSWITCH modules (follow FusionPBX approach)
RUN cp build/modules.conf.in modules.conf \
    # Enable required modules
    && sed -i 's:#applications/mod_callcenter:applications/mod_callcenter:' modules.conf \
    && sed -i 's:#applications/mod_cidlookup:applications/mod_cidlookup:' modules.conf \
    && sed -i 's:#applications/mod_nibblebill:applications/mod_nibblebill:' modules.conf \
    && sed -i 's:#applications/mod_curl:applications/mod_curl:' modules.conf \
    && sed -i 's:#applications/mod_translate:applications/mod_translate:' modules.conf \
    && sed -i 's:#say/mod_say_es:say/mod_say_es:' modules.conf \
    && sed -i 's:#say/mod_say_fr:say/mod_say_fr:' modules.conf \
    # Disable problematic modules (missing dependencies)
    && sed -i 's:applications/mod_signalwire:#applications/mod_signalwire:' modules.conf \
    && sed -i 's:applications/mod_memcache:#applications/mod_memcache:' modules.conf \
    && sed -i 's:formats/mod_shout:#formats/mod_shout:' modules.conf \
    && sed -i 's:formats/mod_sndfile:#formats/mod_sndfile:' modules.conf \
    && sed -i 's:endpoints/mod_skinny:#endpoints/mod_skinny:' modules.conf \
    && sed -i 's:endpoints/mod_verto:#endpoints/mod_verto:' modules.conf

# Build FreeSWITCH
RUN ./bootstrap.sh -j \
    && ./configure -C --enable-portable-binary \
        --disable-dependency-tracking \
        --enable-debug \
        --prefix=/usr/local/freeswitch \
        --enable-core-pgsql-support \
        --disable-mod_erlang_event \
        --without-erlang \
    && make -j $(nproc) && make install

# Stage 2: Runtime image
FROM debian:12

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV FUSIONPBX_VERSION=5.4

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    systemd \
    systemd-sysv \
    dialog \
    nano \
    net-tools \
    nginx \
    snmpd \
    fail2ban \
    supervisor \
    sudo \
    openssl \
    unzip \
    # PHP and extensions
    php8.2 \
    php8.2-fpm \
    php8.2-cli \
    php8.2-common \
    php8.2-curl \
    php8.2-gd \
    php8.2-imap \
    php8.2-mbstring \
    php8.2-mysql \
    php8.2-odbc \
    php8.2-pgsql \
    php8.2-sqlite3 \
    php8.2-xml \
    php8.2-xmlrpc \
    php8.2-zip \
    php8.2-opcache \
    # PostgreSQL
    postgresql-15 \
    postgresql-client-15 \
    postgresql-contrib-15 \
    # Audio libraries for FreeSWITCH
    libogg0 \
    libvorbis0a \
    libflac12 \
    libopus0 \
    libspeex1 \
    libspeexdsp1 \
    libpcre3 \
    libedit2 \
    libsqlite3-0 \
    libcurl4 \
    uuid \
    uuid-runtime \
    libtiff6 \
    libtpl0 \
    && rm -rf /var/lib/apt/lists/*

# Copy FreeSWITCH from builder stage
COPY --from=builder /usr/local/freeswitch /usr/local/freeswitch
COPY --from=builder /usr/local/lib/libsofia-sip-ua.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libspandsp.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libtpl.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libks.so* /usr/local/lib/
COPY --from=builder /usr/local/include/sofia-sip-1.13 /usr/local/include/sofia-sip-1.13

# Update library cache
RUN ldconfig

# Create FusionPBX user and directories
RUN useradd -r -s /bin/false fusionpbx \
    && mkdir -p /var/www/fusionpbx \
    && mkdir -p /etc/fusionpbx \
    && mkdir -p /var/log/fusionpbx \
    && mkdir -p /var/backups/fusionpbx \
    && mkdir -p /usr/local/freeswitch/sounds \
    && mkdir -p /usr/local/freeswitch/recordings

# Download and install FusionPBX
WORKDIR /var/www
RUN wget -O fusionpbx.tar.gz https://github.com/fusionpbx/fusionpbx/archive/refs/heads/5.4.tar.gz \
    && tar -xzf fusionpbx.tar.gz \
    && mv fusionpbx-5.4/* fusionpbx/ \
    && rm -rf fusionpbx-5.4 fusionpbx.tar.gz

# Create FreeSWITCH config directory and set permissions
RUN mkdir -p /etc/freeswitch \
    && mkdir -p /etc/freeswitch/autoload_configs \
    && mkdir -p /var/lib/freeswitch \
    && mkdir -p /var/lib/freeswitch/db \
    && mkdir -p /var/lib/freeswitch/storage \
    && mkdir -p /usr/share/freeswitch/scripts \
    && chown -R www-data:www-data /var/www/fusionpbx \
    && chown -R fusionpbx:fusionpbx /usr/local/freeswitch \
    && chown -R www-data:www-data /etc/freeswitch \
    && chmod -R 775 /etc/freeswitch \
    && chown -R postgres:postgres /var/lib/postgresql

# Configure PHP settings for FusionPBX installation
RUN echo "memory_limit = 512M" >> /etc/php/8.2/fpm/php.ini && \
    echo "max_execution_time = 600" >> /etc/php/8.2/fpm/php.ini && \
    echo "max_input_time = 600" >> /etc/php/8.2/fpm/php.ini && \
    echo "post_max_size = 80M" >> /etc/php/8.2/fpm/php.ini && \
    echo "upload_max_filesize = 80M" >> /etc/php/8.2/fpm/php.ini

# Copy configuration files
COPY config/nginx.conf /etc/nginx/sites-available/fusionpbx
COPY config/php-fpm-fixed.conf /etc/php/8.2/fpm/pool.d/fusionpbx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/fusionpbx-config.conf /fusionpbx-config.conf
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/create-admin.php /create-admin.php

# Configure NGINX
RUN rm -f /etc/nginx/sites-enabled/default \
    && ln -s /etc/nginx/sites-available/fusionpbx /etc/nginx/sites-enabled/fusionpbx

# Make scripts executable
RUN chmod +x /entrypoint.sh /create-admin.php

# Create volumes
VOLUME ["/var/backups/fusionpbx", "/etc/fusionpbx", "/var/lib/postgresql", "/usr/local/freeswitch/recordings", "/var/log"]

# Expose ports
EXPOSE 80 443 8081 5060/tcp 5060/udp 5080/tcp 5080/udp 16384-32768/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
