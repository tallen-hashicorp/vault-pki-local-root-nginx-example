# Use the official NGINX image as a base
FROM nginx:alpine

# Set environment variables
ENV NGINX_CONF /etc/nginx/conf.d/default.conf
ENV CERTS_DIR /etc/nginx/certs

# Copy SSL certificates
COPY nginx_certificate.pem $CERTS_DIR/nginx_certificate.pem
COPY nginx_private_key.pem $CERTS_DIR/nginx_private_key.pem
COPY nginx_cert_chain.pem $CERTS_DIR/nginx_cert_chain.pem

# Copy NGINX configuration file
COPY nginx/nginx.conf $NGINX_CONF

# Copy the index.html file
COPY html /usr/share/nginx/html

# Expose ports
EXPOSE 80 443

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]
