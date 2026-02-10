FROM httpd:alpine
RUN sed -i \
    -e 's/^#LoadModule ssl_module/LoadModule ssl_module/' \
    -e 's/^#LoadModule md_module/LoadModule md_module/' \
    -e 's/^#LoadModule proxy_module/LoadModule proxy_module/' \
    -e 's/^#LoadModule proxy_fcgi_module/LoadModule proxy_fcgi_module/' \
    -e 's/^#LoadModule logio_module/LoadModule logio_module/' \
    -e 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' \
    -e 's/^#LoadModule socache_shmcb_module/LoadModule socache_shmcb_module/' \
    -e 's/^#LoadModule watchdog_module/LoadModule watchdog_module/' \
    /usr/local/apache2/conf/httpd.conf
RUN echo 'Include conf/extra/wordpress.conf' >> /usr/local/apache2/conf/httpd.conf
COPY conf/apache/wordpress.conf /usr/local/apache2/conf/extra/wordpress.conf
