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

  cluster_name=$(yq r ${cluster_file} cluster.name)
  plan_name=$(yq r ${cluster_file} cluster.plan)
  cluster_hostname=$(yq r ${cluster_file} cluster.hostname)
  nodes=$(yq r ${cluster_file} cluster.nodes)
  network_profile=$(yq r ${cluster_file} cluster.network-profile)
  k8s_profile=$(yq r ${cluster_file} cluster.kubernetes-profile)
  compute_profile=$(yq r cluster.yaml --length cluster.compute-profile)
  cluster_tags=$(yq r ${cluster_file} cluster.tags)

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

    if [[ 0 -ne "$compute_profile" ]]; then
        compute_profile_name=$(yq r cluster.yaml cluster.compute-profile.name)

        node_pool_length=$(yq r cluster.yaml --length cluster.compute-profile.node-pool)
        NODE_POOL_SIZING=""
        i=0
        while [[ $node_pool_length -ne 0 ]] ; do
          name=$(yq r cluster.yaml "cluster.compute-profile.node-pool[$i].name")
          instance=$(yq r cluster.yaml "cluster.compute-profile.node-pool[$i].instance")
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
    elif [[ 0 -ne "$compute_profile" ]]; then
        compute_profile_name=$(yq r cluster.yaml cluster.compute-profile.name)
        COMPUTE_PROFILE=$(echo "${CLUSTER}" | jq -r '.compute_profile_name')
        if [[ "$COMPUTE_PROFILE" != "$compute_profile_name" ]]; then
          node_pool_length=$(yq r cluster.yaml --length cluster.compute-profile.node-pool)
          NODE_POOL_SIZING=""
          i=0
          while [[ $node_pool_length -ne 0 ]] ; do
            name=$(yq r cluster.yaml "cluster.compute-profile.node-pool[$i].name")
            instance=$(yq r cluster.yaml "cluster.compute-profile.node-pool[$i].instance")
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

clusters=$(yq r repository/${ENV}/clusters/clusters.yaml -j | jq -r '.clusters[]')

for cluster in ${clusters}; do
  pushd repository/${ENV}/clusters/${cluster}
    create_cluster
  popd
done