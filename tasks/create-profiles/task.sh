#!/bin/bash -e

login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

login_tkgi

pushd repository/${ENV}/kubernetes-profiles
  for file in *.json ; do
    name=$(cat ${file} | jq -r '.name')
    profile_exists=$(tkgi kubernetes-profiles --json | jq --arg profile ${name} '.[] | select(.name==$profile)')
    if [[ -z ${profile_exists} ]]; then
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