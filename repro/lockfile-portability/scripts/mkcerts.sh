set -e
cd /Users/davidlarsen/.claude/jobs/303f71d9/tmp/rig
mkdir -p ca ssl
openssl genrsa -out ca/ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca/ca.key -sha256 -days 365 -out ca/ca.crt \
  -subj "/CN=Mercor Repro Test CA/O=Repro/C=US" 2>/dev/null
openssl genrsa -out ssl/privkey.pem 2048 2>/dev/null
openssl req -new -key ssl/privkey.pem -out ca/server.csr \
  -subj "/CN=sfw.mercor.test/O=Repro/C=US" 2>/dev/null
printf 'subjectAltName=DNS:sfw.mercor.test,DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' > ca/ext.cnf
openssl x509 -req -in ca/server.csr -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
  -out ca/server.crt -days 365 -sha256 -extfile ca/ext.cnf 2>/dev/null
cat ca/server.crt ca/ca.crt > ssl/fullchain.pem
openssl x509 -in ca/server.crt -noout -subject -ext subjectAltName,basicConstraints
