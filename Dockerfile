FROM wordpress:latest

COPY conf/php/*.ini	$PHP_INI_DIR/conf.d/
COPY conf/apache/*.conf	/etc/apache2/sites-available/

RUN a2enmod ssl md
RUN a2ensite wordpress
RUN a2dissite 000-default
