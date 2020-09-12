#!/bin/bash -e

login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

login_tkgi

pushd repository/${ENV}/kubernetes-profiles
  for FILE in *.json ; do 
    tkgi create-kubernetes-profile ${FILE}
  done
popd

pushd repository/${ENV}/network-profiles
  for FILE in *.json ; do 
    tkgi create-network-profile ${FILE}
  done
popd