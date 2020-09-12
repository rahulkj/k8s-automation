#!/bin/bash -e

clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')
protected_namespaces=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.protected_namespaces[]')

login_cluster() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k

  echo "Fetching the cluster information for: ${1}"
  tkgi cluster "${1}"

  echo "Authentication to the cluster: ${1}"
  echo ${pks_password} | tkgi get-credentials "${1}"

  master_ip=$(tkgi cluster ${1} --json | jq -r '.kubernetes_master_ips[0]')
  cluster_hostname=$(tkgi cluster ${1} --json | jq -r '.parameters.kubernetes_master_host')
  sed -i "s/$cluster_hostname/$master_ip/g" ~/.kube/config 
}

is_defined_namespace() {
  is_defined=false
  for defined_namespace in ${2}; do
    if [[ "${1}" == "${defined_namespace}" ]]; then
      is_defined=true
    fi
  done
  echo "${is_defined}"
}

is_protected_namespace() {
  is_protected=false
  for protected_namespace in ${2}; do
    if [[ "${1}" == "${protected_namespace}" ]]; then
      is_protected=true
    fi
  done
  echo "${is_protected}"
}

delete_namespaces() {
  defined_namespaces=$(yq r ${1} -j | jq -r '.cluster.namespaces[]')
  existing_namespaces=$(kubectl get ns -o json | jq -r '.items[].metadata.name')

  for existing_namespace in ${existing_namespaces}; do
    is_defined=$(is_defined_namespace ${existing_namespace} ${defined_namespaces})
    is_protect=$(is_protected_namespace ${existing_namespace} ${protected_namespaces})

    if [[ "${is_defined}" = false && "${is_protect}" = false ]]; then
      set +e
      echo "Deleting namespace: ${existing_namespace}"
      kubectl delete ns ${existing_namespace}
      set -e
    fi
  done
}

echo "clusters: ${clusters}"

for cluster in ${clusters}; do 
  echo "Cluster ${cluster}";
  pushd repository/${ENV}/clusters/${cluster}
    login_cluster ${cluster}
    delete_namespaces cluster.yaml
  popd
done