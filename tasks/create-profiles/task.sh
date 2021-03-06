#!/bin/bash -e

login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials --product-name pivotal-container-service --credential-reference ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

login_tkgi

create_etcd_encryption_file() {

encryption_key=''

set +e
ENCRYPTION_KEY=$(credhub f -n /${CREDHUB_PREFIX}/encryption_key)
set -e

if [[ -z "${ENCRYPTION_KEY}" ]]; then
  encryption_key=$(head -c 32 /dev/urandom | base64)
  credhub set -n /${CREDHUB_PREFIX}/encryption_key -t value -v ${encryption_key}
else
  encryption_key=$(credhub get -n /${CREDHUB_PREFIX}/encryption_key -q)
fi

cat > encryption-provider-config.yml <<EOF
---
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: $encryption_key
EOF
}

pushd repository/${ENV}/kubernetes-profiles
  for file in *.json ; do
    name=$(cat ${file} | jq -r '.name')
    profile_exists=$(tkgi kubernetes-profiles --json | jq --arg profile ${name} '.[] | select(.name==$profile)')
    if [[ -z ${profile_exists} ]]; then
      create_etcd_encryption_file
      tkgi create-kubernetes-profile ${file}
    else
      echo "Skipping creating kubernetes profile: ${name}"
    fi
  done
popd

pushd repository/${ENV}/network-profiles
  for file in *.json ; do
    name=$(cat ${file} | jq -r '.name')
    profile_exists=$(tkgi network-profiles --json | jq --arg profile ${name} '.[] | select(.name==$profile)')
    if [[ -z ${profile_exists} ]]; then
      tkgi create-network-profile ${file}
    else
      echo "Skipping creating network profile: ${name}"
    fi
  done
popd

pushd repository/${ENV}/compute-profiles
  for file in *.json ; do
    name=$(cat ${file} | jq -r '.name')
    profile_exists=$(tkgi compute-profiles --json | jq --arg profile ${name} '.[] | select(.name==$profile)')
    if [[ -z ${profile_exists} ]]; then
      tkgi create-compute-profile ${file}
    else
      echo "Skipping creating compute profile: ${name}"
    fi
  done
popd