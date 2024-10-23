# vault-pki-local-root-nginx-example

## Create a Root Certificate Authority (CA)
```bash
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt
```

You will be prompted for details such as the country, organization name, and Common Name (CN). For a root CA, the CN typically refers to something like "My Root CA."]

**Add the `rootCA.crt` to the trust keychain to trust**
1. Open keychain
2. Select System Keychains > System
3. Drag the `rootCA.crt` from finder to this
4. Select Get Info on new cert
5. Set to always trust

Your laptop will now trust antying this signs or makes


## Create an Intermediate CA in Vault
This step assumes you have vault running and can access it. If you are lazy you can run `./lazy.sh`
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

# Sign the CSR
openssl x509 -req -in pki_intermediate.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out intermediate-cert.pem -days 3650 -sha256 -extfile ca-ext.cnf -extensions v3_ca

cat intermediate-cert.pem rootCA.crt > intermediate-bundle.pem

# Set the signed intermediate certificate
vault write pki_int/intermediate/set-signed certificate=@intermediate-bundle.pem
```

## Define role and request cert for NGINX
```bash
# Define roles for the intermediate CA
vault write pki_int/roles/example-dot-com \
     issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
     allowed_domains="example.com" \
     allow_subdomains=true \
     max_ttl="720h"

# Generate a new cert
vault write -format=json pki_int/issue/example-dot-com common_name="test.example.com" ttl="24h" > nginx_certs.json

# Extract private key, certificate, and CA chain
jq -r '.data.private_key' nginx_certs.json > nginx_private_key.pem
jq -r '.data.certificate' nginx_certs.json > nginx_certificate.pem
jq -r '.data.issuing_ca' nginx_certs.json > nginx_issuing_ca.pem
jq -r '.data.ca_chain | join("\n")' nginx_certs.json > nginx_chain.pem

openssl verify -CAfile nginx_chain.pem nginx_certificate.pem
```