#!/bin/bash

# Enable the intermediate PKI secrets engine
vault secrets enable -path=pki_int pki

# Configure the intermediate PKI engine
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate an intermediate CA
vault write -format=json pki_int/intermediate/generate/internal \
     common_name="example.com Intermediate Authority" \
     issuer_name="example-dot-com-intermediate" \
     | jq -r '.data.csr' > pki_intermediate.csr

# Sign the CSR
openssl x509 -req -in pki_intermediate.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out intermediate-cert.pem -days 3650 -sha256 -extfile ca-ext.cnf -extensions v3_ca

cat intermediate-cert.pem rootCA.crt > intermediate-bundle.pem

# Set the signed intermediate certificate in Vault
vault write pki_int/intermediate/set-signed certificate=@intermediate-bundle.pem

# Define roles for the intermediate CA
vault write pki_int/roles/example-dot-com \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="example.com" \
     allow_subdomains=true \
     max_ttl="720h"

vault write pki_int/roles/local-host \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="127.0.0.1,localhost" \
     allow_subdomains=true \
     allow_bare_domains=true
     max_ttl="720h"

# Generate a new certificate
vault write -format=json pki_int/issue/local-host common_name="localhost" ttl="24h" > nginx_certs.json

# Extract private key, certificate, and CA chain
jq -r '.data.private_key' nginx_certs.json > nginx_private_key.pem
jq -r '.data.certificate' nginx_certs.json > nginx_certificate.pem
jq -r '.data.issuing_ca' nginx_certs.json > nginx_issuing_ca.pem
jq -r '.data.ca_chain | join("\n")' nginx_certs.json > nginx_chain.pem
cat nginx_certificate.pem nginx_chain.pem > nginx_cert_chain.pem

# Verify the newly issued certificate
openssl verify -CAfile nginx_chain.pem nginx_certificate.pem