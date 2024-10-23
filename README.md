# Vault PKI Local Root NGINX Example

> **Note:** Please manually complete **Step 1** to create the Root Certificate Authority (CA). After that, you can simply run the `./lazy.sh` script to continue with the remaining steps.

## Overview
This guide outlines the steps to create a Root Certificate Authority (CA), configure an Intermediate CA in HashiCorp Vault, define roles, and generate certificates for use with NGINX.

## Step 1: Create a Root Certificate Authority (CA)
To create a root CA, execute the following commands:

```bash
# Generate a private key for the root CA
openssl genrsa -out rootCA.key 4096

# Create a self-signed root CA certificate
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt
```
You will be prompted to enter details such as your country, organization name, and Common Name (CN). For a root CA, the CN typically refers to something like "My Root CA."

### Trust the Root CA
To trust your newly created root CA, add `rootCA.crt` to your system's trust keychain:

1. Open **Keychain Access**.
2. Select **System Keychains** > **System**.
3. Drag `rootCA.crt` from Finder into this section.
4. Right-click the new certificate and select **Get Info**.
5. Set the certificate to **Always Trust**.

Your laptop will now trust anything that this CA signs.

---

## Step 2: Create an Intermediate CA in Vault
Ensure you have Vault running and accessible. If you want to automate this, you can run `./lazy.sh`.

```bash
# Enable the intermediate PKI secrets engine
vault secrets enable -path=pki_int pki

# Configure the intermediate PKI engine with a max lease TTL
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate an intermediate CA certificate signing request (CSR)
vault write -format=json pki_int/intermediate/generate/internal \
     common_name="My Awsome Intermediate Authority" \
     issuer_name="my-awsome-intermediate" \
     | jq -r '.data.csr' > pki_intermediate.csr

# Sign the CSR with the root CA
openssl x509 -req -in pki_intermediate.csr -CA rootCA.crt -CAkey rootCA.key \
     -CAcreateserial -out intermediate-cert.pem -days 3650 -sha256 -extfile ca-ext.cnf -extensions v3_ca

# Create an intermediate bundle by combining the signed intermediate certificate and root CA certificate
cat intermediate-cert.pem rootCA.crt > intermediate-bundle.pem

# Set the signed intermediate certificate in Vault
vault write pki_int/intermediate/set-signed certificate=@intermediate-bundle.pem
```

## Step 3: Define Role and Request Certificate for NGINX
Next, define roles in Vault for your intermediate CA and request a certificate for NGINX.

```bash
# Define roles for the intermediate CA
vault write pki_int/roles/local-host \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="127.0.0.1,localhost" \
     allow_subdomains=true \
     allow_bare_domains=true \
     max_ttl="720h"

# Generate a new certificate for the local host
vault write -format=json pki_int/issue/local-host common_name="localhost" ttl="24h" > nginx_certs.json

# Extract private key, certificate, and CA chain from the issued certificate
jq -r '.data.private_key' nginx_certs.json > nginx_private_key.pem
jq -r '.data.certificate' nginx_certs.json > nginx_certificate.pem
jq -r '.data.issuing_ca' nginx_certs.json > nginx_issuing_ca.pem
jq -r '.data.ca_chain | join("\n")' nginx_certs.json > nginx_chain.pem

# Combine the certificate and CA chain for use with NGINX
cat nginx_certificate.pem nginx_chain.pem > nginx_cert_chain.pem

# Verify the newly issued certificate against the issuing CA
openssl verify -CAfile nginx_chain.pem nginx_certificate.pem
```

## Step 4: Run NGINX in Docker
Build and run your NGINX container using the generated certificates.

```bash
# Build the Docker image for NGINX
docker build -t vault-nginx .

# Run the NGINX container with ports mapped
docker run --rm -p 80:80 -p 443:443 vault-nginx

# Alternatively, run a shell in the NGINX container for debugging
docker run --rm -it -p 80:80 -p 443:443 vault-nginx /bin/sh
```

Now vist [https://localhost](https://localhost)