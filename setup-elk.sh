#!/usr/bin/env bash
set -euo pipefail

# Plik wyjsciowy z haslami
CRED_FILE="$(pwd)/credentials.txt"

# Funkcja czyszczaca - zawsze wyswietla hasla po zakonczeniu
cleanup() {
    if [ -f "$CRED_FILE" ]; then
        echo -e "\n\033[1;36m[INFO]\033[0m Password summary saved to: $CRED_FILE"
        cat "$CRED_FILE"
    fi
}
trap cleanup EXIT

log_step() {
    echo -e "\033[1;32m[+]\033[0m $1..."
}

### Step 1: Cleanup
log_step "Stopping services and cleaning up"
systemctl stop elasticsearch kibana apm-server 2>/dev/null || true
rm -rf /etc/elasticsearch/certs/*

### Step 2: JVM Memory
mkdir -p /etc/elasticsearch/jvm.options.d/
echo "-Xms2g" | tee /etc/elasticsearch/jvm.options.d/memory.options > /dev/null
echo "-Xmx2g" | tee -a /etc/elasticsearch/jvm.options.d/memory.options > /dev/null

### Step 3: ES Config
log_step "Writing elasticsearch.yml"
tee /etc/elasticsearch/elasticsearch.yml > /dev/null << 'EOF'
cluster.name: elasticsearch
node.name: ALFA-SPEECH-ANALYZER-BACKEND
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
discovery.type: single-node
xpack.security.enabled: true
EOF

### Step 4: TLS & Start
log_step "Generating certificates"
/usr/share/elasticsearch/bin/elasticsearch-certutil ca --out /etc/elasticsearch/certs/http_ca.p12 --pass "" --silent
/usr/share/elasticsearch/bin/elasticsearch-certutil cert --ca /etc/elasticsearch/certs/http_ca.p12 --ca-pass "" --out /etc/elasticsearch/certs/http.p12 --pass "" --ip 127.0.0.1 --dns localhost --silent
openssl pkcs12 -in /etc/elasticsearch/certs/http_ca.p12 -clcerts -nokeys -out /etc/elasticsearch/certs/http_ca.crt -passin pass:""

chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs
chmod 600 /etc/elasticsearch/certs/*.p12
chmod 644 /etc/elasticsearch/certs/*.crt

tee -a /etc/elasticsearch/elasticsearch.yml > /dev/null << 'EOF'
xpack.security.http.ssl:
  enabled: true
  keystore.path: certs/http.p12
xpack.security.transport.ssl:
  enabled: true
  verification_mode: certificate
  keystore.path: certs/http.p12
  truststore.path: certs/http.p12
EOF

systemctl daemon-reload
systemctl start elasticsearch
sleep 10 # Czekamy na pelny start ES

log_step "Generating credentials"
ELASTIC_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s | tr -d '\r\n ')
KIBANA_SYSTEM_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -b -s | tr -d '\r\n ')

echo "ELASTIC_PASSWORD: $ELASTIC_PASSWORD" > "$CRED_FILE"
echo "KIBANA_SYSTEM_PASSWORD: $KIBANA_SYSTEM_PASSWORD" >> "$CRED_FILE"
chmod 600 "$CRED_FILE"

### Step 5: Kibana
log_step "Configuring Kibana"
mkdir -p /etc/kibana/certs
\cp /etc/elasticsearch/certs/http_ca.crt /etc/kibana/certs/

tee /etc/kibana/kibana.yml > /dev/null << EOF
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["https://127.0.0.1:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "$KIBANA_SYSTEM_PASSWORD"
elasticsearch.ssl.certificateAuthorities: [ "/etc/kibana/certs/http_ca.crt" ]
xpack.encryptedSavedObjects.encryptionKey: "$(openssl rand -base64 32)"
EOF

chown -R kibana:kibana /etc/kibana
systemctl restart kibana

### Step 6: APM Server
log_step "Configuring APM Server"
mkdir -p /etc/apm-server/certs
\cp /etc/elasticsearch/certs/http_ca.crt /etc/apm-server/certs/

tee /etc/apm-server/apm-server.yml > /dev/null << EOF
apm-server:
  host: "127.0.0.1:8200"
  auth:
    anonymous:
      enabled: true
      allow_anonymous: true

output.elasticsearch:
  hosts: ["https://127.0.0.1:9200"]
  username: "elastic"
  password: "$ELASTIC_PASSWORD"
  ssl:
    certificate_authorities: ["/etc/apm-server/certs/http_ca.crt"]
EOF

chown -R apm-server:apm-server /etc/apm-server
systemctl restart apm-server

echo -e "\n\033[1;32m[SUCCESS]\033[0m ELK Stack is configured."