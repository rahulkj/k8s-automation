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

  CLUSTER_EXISTS=$(tkgi clusters --json | jq --arg cluster_name ${cluster_name} '.[] | select(.name==$cluster_name)')

  if [[ -z ${CLUSTER_EXISTS} ]]; then

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
    check_status ${cluster}
  else
    echo "Skipping cluster creation"
  fi
}

check_status() {
  cluster_status=$(tkgi cluster ${1} --json | jq -r '.last_action_state')
  while [[ "${cluster_status}" != "succeeded" && "${cluster_status}" != "failed" ]]; do
    printf "."
    sleep 30
    cluster_status=$(tkgi cluster ${1} --json | jq -r '.last_action_state')
  done

  echo "Cluster ${1} status is: ${status}"
}

login_tkgi

clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')

echo "clusters: ${clusters}"

for cluster in ${clusters}; do 
  echo "Cluster ${cluster}";
  pushd repository/${ENV}/clusters/${cluster}
    create_cluster
  popd
done