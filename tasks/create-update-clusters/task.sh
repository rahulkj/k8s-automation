#!/bin/bash -e

login_tkgi() {
  pks_password=$(om -t "${OM_TARGET}" credentials --product-name pivotal-container-service --credential-reference ".properties.uaa_admin_password" -t json | jq -r '.secret')

  tkgi login -a ${PKS_API_ENDPOINT} -u admin -p ${pks_password} -k
}

validateIfTagsExist() {
  exists=true
  cluster="${1}"
  cluster_tags="${2}"

  IFS=',' read -ra TAGS <<< "${cluster_tags}"
  for tag in "${TAGS[@]}"; do
    KEY=$(echo "$tag" | cut -d':' -f1)
    VALUE=$(echo "$tag" | cut -d':' -f2)

    DATA=$(echo "${cluster}" | jq -r --arg key ${KEY} '.parameters.cluster_tags[] | select(.name==$key) | .value')
    if [[ -z "${DATA}" || "${VALUE}" != "${DATA}" ]]; then
      exists=false
      break
    fi
  done

  echo ${exists}
}

create_cluster() {
  cluster_file=cluster.yaml

  cluster_name=$(yq e .cluster.name ${cluster_file})
  plan_name=$(yq e .cluster.plan ${cluster_file})
  cluster_hostname=$(yq e .cluster.hostname ${cluster_file})
  nodes=$(yq e .cluster.nodes ${cluster_file})
  network_profile=$(yq e .cluster.network-profile ${cluster_file})
  k8s_profile=$(yq e .cluster.kubernetes-profile ${cluster_file})
  compute_profile_name=$(yq e .cluster.compute-profile.name cluster.yaml)
  cluster_tags=$(yq e .cluster.tags ${cluster_file})

  echo "Cluster ${cluster}";
  CLUSTER=$(tkgi clusters --json | jq --arg cluster_name ${cluster_name} '.[] | select(.name==$cluster_name)')

  if [[ -z ${CLUSTER} ]]; then

    CMD="tkgi create-cluster ${cluster_name} -p ${plan_name} -e ${cluster_hostname}"

    if [[ ! -z "$network_profile" ]]; then
      CMD="${CMD} --network-profile ${network_profile}"
    fi

    if [[ ! -z "$k8s_profile" ]]; then
      CMD="${CMD} --kubernetes-profile ${k8s_profile}"
    fi

    if [[ ! -z "$compute_profile_name" ]]; then
      node_pool_length=$(yq eval '.cluster.compute-profile.node-pool | length' cluster.yaml)
      NODE_POOL_SIZING=""
      i=0
      while [[ $node_pool_length -ne 0 ]] ; do
        name=$(yq e ".cluster.compute-profile.node-pool[$i].name" cluster.yaml)
        instance=$(yq e ".cluster.compute-profile.node-pool[$i].instance" cluster.yaml)
        if [[ $i -eq 0 ]]; then
          NODE_POOL_SIZING="$name:$instance"
        else
          NODE_POOL_SIZING="$NODE_POOL_SIZING,$name:$instance"
        fi
        i=$[$i+1]
        node_pool_length=$[$node_pool_length-1]
      done

      CMD="${CMD} --compute-profile ${compute_profile_name}"

      if [[ ! -z "$NODE_POOL_SIZING" ]]; then
        CMD="${CMD} --node-pool-instances ${NODE_POOL_SIZING}"
      fi
    elif [[ ! -z "${nodes}" ]]; then
      CMD="${CMD} -n ${nodes}"
    fi

    if [[ ! -z "$cluster_tags" ]]; then
        CMD="${CMD} --tags ${cluster_tags}"
    fi

    ${CMD}
    check_status ${cluster_name}
  else
    echo "Skipping cluster ${cluster_name} creation, and checking if cluster needs to be updated..."

    CMD="tkgi update-cluster ${cluster_name} --non-interactive"
    is_updated=false

    CURRENT_NODES=$(echo "${CLUSTER}" | jq -r '.parameters.kubernetes_worker_instances')

    if [[ ! -z "${nodes}" ]]; then
      if [[ "${CURRENT_NODES}" != "${nodes}" ]]; then
        CMD="${CMD} --num-nodes ${nodes}"
        is_updated=true
      fi
    elif [[ ! -z "$compute_profile_name" ]]; then
      COMPUTE_PROFILE=$(echo "${CLUSTER}" | jq -r '.compute_profile_name')
      if [[ "$COMPUTE_PROFILE" != "$compute_profile_name" ]]; then
        node_pool_length=$(yq eval '.cluster.compute-profile.node-pool | length' cluster.yaml)
        NODE_POOL_SIZING=""
        i=0
        while [[ $node_pool_length -ne 0 ]] ; do
          name=$(yq e ".cluster.compute-profile.node-pool[$i].name" cluster.yaml)
          instance=$(yq e ".cluster.compute-profile.node-pool[$i].instance" cluster.yaml)
          if [[ $i -eq 0 ]]; then
            NODE_POOL_SIZING="$name:$instance"
          else
            NODE_POOL_SIZING="$NODE_POOL_SIZING,$name:$instance"
          fi
          i=$[$i+1]
          node_pool_length=$[$node_pool_length-1]
        done

        CMD="${CMD} --compute-profile ${compute_profile_name}"

        if [[ ! -z "$NODE_POOL_SIZING" ]]; then
          CMD="${CMD} --node-pool-instances ${NODE_POOL_SIZING}"
        fi
        is_updated=true
      fi
    fi

    if [[ ! -z "${cluster_tags}" ]]; then
      allTagsExist=$(validateIfTagsExist "${CLUSTER}" "${cluster_tags}")
      if [[ "${allTagsExist}" = false ]]; then
        CMD="${CMD} --tags ${cluster_tags}"
        is_updated=true
      fi
    fi

    if [[ "${is_updated}" = true ]]; then
      echo "Updating cluster ${cluster_name} ..."
      ${CMD}
      check_status ${cluster_name}
      
      echo "--- Cluster Details Begin: ----\n"

      tkgi cluster ${cluster_name}

      echo "--- Cluster Details End: ---- \n\n"
    else
      echo "Skipping update cluster ${cluster_name}, as there is no change in number of nodes, or tags"
    fi
  fi
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

clusters=$(yq e repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')

for cluster in ${clusters}; do
  pushd repository/${ENV}/clusters/${cluster}
    create_cluster
  popd
done