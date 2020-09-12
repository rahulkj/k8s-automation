#!/bin/bash

login_cluster() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k

  echo "Fetching the cluster information for: ${1}"
  tkgi cluster "${1}"

  echo "Authentication to the cluster: ${1}"
  echo ${pks_password} | tkgi get-credentials "${1}"
}

create_namespace() {
  CMD="kubectl create -f namespaces.yaml"
  ${CMD}
}

clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')

echo "clusters: ${clusters}"

for cluster in ${clusters}; do 
  echo "Cluster ${cluster}";
  pushd repository/${ENV}/clusters/${cluster}
    login_cluster ${cluster}
    create_namespace
  popd
done