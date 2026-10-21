FROM php:8.4.26-apache

# Lab php.ini: upload progress enabled + cleanup off + permissive session
# ids. That is the substrate the "php2shell" demos ride on.
# INTENTIONALLY VULNERABLE. Local lab only, never expose this container.
COPY php.ini /usr/local/etc/php/php.ini

RUN mkdir -p /var/lib/php/sessions \
 && chown -R www-data:www-data /var/lib/php/sessions

COPY web/ /var/www/html/
RUN chown -R root:root /var/www/html && chmod -R 755 /var/www/html

# CTF flag: readable by the web user, no other path to it.
RUN printf 'flag{php2shell_lab_109619_chain}\n' > /flag && chmod 644 /flag

EXPOSE 80
