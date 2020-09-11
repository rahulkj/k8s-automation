#!/bin/bash -e

chmod +x tkgi/*
chmod +x kubectl/*

mv tkgi/tkgi* tkgi/tkgi
mv kubectl/kubectl* kubectl/kubectl

TKGI_CMD=./tkgi/tkgi
KUBECTL_CMD=./kubectl/kubectl

function login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  $TKGI_CMD login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

login_tkgi

pushd repository/${ENV}/kubernetes-profiles
  for FILE in *.json ; do 
    echo "$TKGI_CMD create-kubernetes-profile ${FILE}"
  done
popd

pushd repository/${ENV}/network-profiles
  for FILE in *.json ; do 
    echo "$TKGI_CMD create-network-profile ${FILE}"
  done
popd