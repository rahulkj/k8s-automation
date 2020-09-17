#!/bin/bash -e

login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials -p pivotal-container-service -c ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

create_cluster() {
  cluster_file=cluster.yaml

  cluster_name=$(yq r ${cluster_file} cluster.name)
  plan_name=$(yq r ${cluster_file} cluster.plan)
  cluster_hostname=$(yq r ${cluster_file} cluster.hostname)
  nodes=$(yq r ${cluster_file} cluster.nodes)
  network_profile=$(yq r ${cluster_file} cluster.network-profile)
  k8s_profile=$(yq r ${cluster_file} cluster.kubernetes-profile)
  cluster_tags=$(yq r ${cluster_file} cluster.tags)

  echo "Cluster ${cluster}";
  CLUSTER=$(tkgi clusters --json | jq --arg cluster_name ${cluster_name} '.[] | select(.name==$cluster_name)')

  if [[ -z ${CLUSTER} ]]; then

    CMD="tkgi create-cluster ${cluster_name} -p ${plan_name} -e ${cluster_hostname} -n ${nodes}"

    if [[ ! -z "$network_profile" ]]; then
        CMD="${CMD} --network-profile ${network_profile}"
    fi

    if [[ ! -z "$k8s_profile" ]]; then
        CMD="${CMD} --kubernetes-profile ${k8s_profile}"
    fi

    if [[ ! -z "$cluster_tags" ]]; then
        CMD="${CMD} --tags ${cluster_tags}"
    fi

    ${CMD}
  else
    echo "Skipping cluster ${cluster} creation, and checking if cluster needs to be updated..."

    CMD="tkgi update-cluster ${cluster_name} --non-interactive"
    is_updated=false

    CURRENT_NODES=$(echo "${CLUSTER}" | jq -r '.parameters.kubernetes_worker_instances')
    if [[ "${CURRENT_NODES}" != "${nodes}" ]]; then
       CMD="${CMD} --num-nodes ${nodes}"
       is_updated=true
    fi

    if [[ ! -z "$cluster_tags" ]]; then
        CMD="${CMD} --tags ${cluster_tags}"
        is_updated=true
    fi

    if [[ "${is_updated}" = true ]]; then
      echo "Updating cluster ${cluster} ..."
      ${CMD}
    else
      echo "Skipping update cluster ${cluster}, as there is no change in number of nodes, or tags"
    fi
  fi

  check_status ${cluster}
}

check_status() {
  echo "Waiting for cluster ${1} creation to finish..."

  cluster_status=$(tkgi cluster ${1} --json | jq -r '.last_action_state')
  while [[ "${cluster_status}" != "succeeded" && "${cluster_status}" != "failed" ]]; do
    printf "."
    sleep 30
    cluster_status=$(tkgi cluster ${1} --json | jq -r '.last_action_state')
  done

  echo ""
  echo "Cluster ${1} status is: ${cluster_status}"
}

login_tkgi

clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')

for cluster in ${clusters}; do
  pushd repository/${ENV}/clusters/${cluster}
    create_cluster
  popd
done