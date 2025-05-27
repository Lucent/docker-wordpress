FROM wordpress:latest

COPY php/*.ini		$PHP_INI_DIR/conf.d/
COPY apache/*.conf	/etc/apache2/sites-available/

RUN a2enmod ssl md
RUN a2ensite wordpress
RUN a2dissite 000-default
