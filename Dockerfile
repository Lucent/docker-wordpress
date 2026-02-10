FROM httpd:alpine
RUN echo 'Include conf/extra/wordpress.conf' >> /usr/local/apache2/conf/httpd.conf
COPY conf/apache/wordpress.conf /usr/local/apache2/conf/extra/wordpress.conf
