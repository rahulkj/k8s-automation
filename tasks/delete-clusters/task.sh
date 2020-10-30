#!/bin/bash -e

login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

login_tkgi

existing_clusters=$(tkgi clusters --json | jq -r '.[].name')

defined_clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')
protected_clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.protected_clusters[]')

is_protected_cluster() {
  is_protected=false
  for protected_cluster in ${protected_clusters}; do
    if [[ "${protected_cluster}" == "${1}" ]]; then
      is_protected=true
      break
    fi
  done
  echo "${is_protected}"
}

is_removed_cluster() {
  is_removed=true
  for defined_cluster in ${defined_clusters}; do
    if [[ "${defined_cluster}" == "${1}" ]]; then
      is_removed=false
    fi
  done
  echo "${is_removed}"
}

for cluster in ${existing_clusters}; do
  is_protected=$(is_protected_cluster ${cluster})
  is_removed=$(is_removed_cluster ${cluster})

  if [[ "${is_protected}" = false && "${is_removed}" = true ]]; then  
    cluster_status=$(tkgi cluster ${cluster} --json | jq -r '.last_action_state')
    if [[ "${cluster_status}" == "in progress" ]]; then
      echo "Skipping delete as the cluster is being deleted"
    else
      tkgi delete-cluster ${cluster} --non-interactive --wait
    fi
  fi

done