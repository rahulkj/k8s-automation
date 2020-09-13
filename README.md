TKGI k8s Automation Pipeline
---

## Motivation

This project was created to aid k8s cluster creation and management. The pipeline currently is based on [Tanzu Kubernetes Grid Integrated (TKGI)](https://network.pivotal.io/products/pivotal-container-service/).

This pipeline creates TKGI clusters based on the entires in `clusters/clusters.yaml`

```
.
├── LICENSE
├── README.md
├── environments
│   └── homelab
│       ├── clusters
│       │   ├── clusters.yaml
│       │   ├── k8s1
│       │   │   └── cluster.yaml
│       │   ├── k8s2
│       │   │   └── cluster.yaml
│       │   └── k8s3
│       │       └── cluster.yaml
│       ├── kubernetes-profiles
│       │   └── etcd-k8s-profile.json
│       └── network-profiles
│           ├── dedicated-network-profile.json
│           └── default-network-profile.json
├── pipelines
│   ├── params.yml
│   └── pipeline.yml
└── tasks
    ├── create-cluster
    │   ├── task.sh
    │   └── task.yml
    ├── create-namespaces
    │   ├── task.sh
    │   └── task.yml
    ├── create-profiles
    │   ├── task.sh
    │   └── task.yml
    ├── delete-cluster
    │   ├── task.sh
    │   └── task.yml
    └── delete-namespaces
        ├── task.sh
        └── task.yml
```

Place the k8s cluster details in their respective folders. 

Currently the pipeline does the following:
- Creates kubernetes profiles _(if defined)_
- Creates network profiles _(if defined)_
- Creates kubernetes clusters
- Deletes unmanaged clusters
- Creates namespaces
- Deletes unmanaged namespaces

Feel free to extend this pipeline to suit your needs.

## Pipeline

To fly the pipeline, fill out the `params.yml` with the relevant details, and then fly the pipeline

`fly -t target sp -p k8s -c pipelines/pipeline.yml -l pipelines/params.yml`

Before you run the pipeline, secure your secrets into credhub.