# vault-pki-local-root-nginx-example

## Create a Root Certificate Authority (CA)
To create a root CA, execute the following commands:

```bash
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt
```

You will be prompted to enter details such as your country, organization name, and Common Name (CN). For a root CA, the CN typically refers to something like "My Root CA."

### Trust the Root CA
To trust your newly created root CA, add `rootCA.crt` to your system's trust keychain:

1. Open Keychain Access.
2. Select `System Keychains` > `System`.
3. Drag `rootCA.crt` from Finder into this section.
4. Right-click the new certificate and select `Get Info`.
5. Set the certificate to always trust.

Your laptop will now trust anything that this CA signs.

## Create an Intermediate CA in Vault
This step assumes you have Vault running and accessible. If you want to automate this, you can run `./lazy.sh`.

```bash
# Enable the intermediate PKI secrets engine
vault secrets enable -path=pki_int pki

# Configure the intermediate PKI engine
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate an intermediate CA
vault write -format=json pki_int/intermediate/generate/internal \
     common_name="example.com Intermediate Authority" \
     issuer_name="example-dot-com-intermediate" \
     | jq -r '.data.csr' > pki_intermediate.csr

# Sign the CSR with the root CA
openssl x509 -req -in pki_intermediate.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out intermediate-cert.pem -days 3650 -sha256 -extfile ca-ext.cnf -extensions v3_ca

# Create an intermediate bundle
cat intermediate-cert.pem rootCA.crt > intermediate-bundle.pem

# Set the signed intermediate certificate in Vault
vault write pki_int/intermediate/set-signed certificate=@intermediate-bundle.pem
```

## Define Role and Request Certificate for NGINX
Next, define a role in Vault for your intermediate CA and request a certificate for NGINX.

```bash
# Define roles for the intermediate CA
vault write pki_int/roles/example-dot-com \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="example.com" \
     allow_subdomains=true \
     max_ttl="720h"

# Generate a new certificate
vault write -format=json pki_int/issue/example-dot-com common_name="test.example.com" ttl="24h" > nginx_certs.json

# Extract private key, certificate, and CA chain
jq -r '.data.private_key' nginx_certs.json > nginx_private_key.pem
jq -r '.data.certificate' nginx_certs.json > nginx_certificate.pem
jq -r '.data.issuing_ca' nginx_certs.json > nginx_issuing_ca.pem
jq -r '.data.ca_chain | join("\n")' nginx_certs.json > nginx_chain.pem

# Verify the newly issued certificate
openssl verify -CAfile nginx_chain.pem nginx_certificate.pem
```