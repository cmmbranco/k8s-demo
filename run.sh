#!/bin/bash


## Launcher
if [ $1 == 'start' ]
then
    minikube config set memory 3500
    minikube config set cpus 2
    # minikube config set vm-driver virtualbox
    minikube start
    minikube addons enable metrics-server

fi

## Destroy minikube
if [ $1 == 'delete' ]
then
    minikube delete
fi


if [ $1 == 'restart' ]
then
  minikube delete
  minikube start
fi


## Setup the applications
if [ $1 == 'setup' ]
then

    eval $(minikube docker-env)

    ## Create namespaces
    minikube kubectl -- apply -f deploymentFiles/namespaces/hellopyNamespace.yaml
    minikube kubectl -- apply -f deploymentFiles/namespaces/kibanaNamespace.yaml
    minikube kubectl -- apply -f deploymentFiles/namespaces/elasticNamespace.yaml
    minikube kubectl -- apply -f deploymentFiles/namespaces/logstashNamespace.yaml
    minikube kubectl -- apply -f deploymentFiles/namespaces/filebeatNamespace.yaml
    minikube kubectl -- apply -f deploymentFiles/namespaces/argoNamespace.yaml

    ## build images to registry
    cd apps/pythonApp/
    docker build -f dockerPythonServer.docker -t hello-python:latest .
    cd ../../

    ## deploy applications from registry and other sources
    minikube kubectl -- apply -f deploymentFiles/pythonServer/hellopyDeployment.yaml
    minikube kubectl -- apply -f deploymentFiles/pythonServer/hellopyService.yaml

    minikube kubectl -- apply -f deploymentFiles/elastic/elasticService2.yaml
    minikube kubectl -- apply -f deploymentFiles/elastic/elasticDeployment2.yaml


    minikube kubectl -- apply -f deploymentFiles/logstash/logstashDeployment.yaml
    minikube kubectl -- apply -f deploymentFiles/logstash/logstashService.yaml

    minikube kubectl -- apply -f deploymentFiles/filebeat/metricserverDeployment.yaml
    minikube kubectl -- apply -f deploymentFiles/filebeat/metricserverService.yaml


    minikube kubectl -- apply -f deploymentFiles/filebeat/filebeatDeployment.yaml
    minikube kubectl -- apply -f deploymentFiles/filebeat/metricbeatDeployment.yaml

    minikube kubectl -- apply -f deploymentFiles/kibana/kibanaDeployment2.yaml
    minikube kubectl -- apply -f deploymentFiles/kibana/kibanaService2.yaml

    minikube kubectl -- apply -n argocd-ns -f deploymentFiles/argoCD/argoDeployment.yaml
    minikube kubectl -- apply -n argocd-ns -f deploymentFiles/argoCD/argoService.yaml

    minikube kubectl -- apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    minikube kubectl -- apply -f deploymentFiles/curator/curator-cronjob.yaml


    minikube kubectl -- patch svc argocd-server -n argocd-ns -p '{"spec": {"type": "LoadBalancer"}}'


    echo 'Argo PW:'
    minikube kubectl -- get pods -n argocd-ns -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2

    ## MongoDB workaround!!!!!

    # Create keyfile for the MongoDB cluster as a Kubernetes shared secret
    TMPFILE=$(mktemp)
    /usr/bin/openssl rand -base64 741 > $TMPFILE
    minikube kubectl -- create secret generic shared-bootstrap-data --from-file=internal-auth-mongodb-keyfile=$TMPFILE
    rm $TMPFILE

    # Create mongodb service with mongod stateful-set
    # Quick Hack (needs fixing): Temporarily added no-valudate due to k8s 1.8 bug: https://github.com/kubernetes/kubernetes/issues/53309
    minikube kubectl -- apply -f deploymentFiles/mongo/mongoDeploy.yaml --validate=false

    ## ROOK/CEPH
    ## See 2 node configuration schema further down, required rook library

fi


## Clean deployment
if [ $1 == 'teardown' ]
then

    ## Delete exposed service list (!!!Do not uncomment this block, services should be exposed properly (file decl.)!!!)
    ## Use to understand service registry

    # minikube kubectl -- delete service hello-python-service
    # minikube kubectl -- delete service elasticsearch-logging-service
    # minikube kubectl -- delete service logstash-service


    ## Delete applications
    minikube kubectl -- delete -f deploymentFiles/pythonServer/hellopyDeployment.yaml
    minikube kubectl -- delete -f deploymentFiles/pythonServer/hellopyService.yaml

    minikube kubectl -- delete -f deploymentFiles/elastic/elasticDeployment2.yaml
    minikube kubectl -- delete -f deploymentFiles/elastic/elasticService2.yaml

    minikube kubectl -- delete -f deploymentFiles/logstash/logstashDeployment.yaml
    minikube kubectl -- delete -f deploymentFiles/logstash/logstashService.yaml

    minikube kubectl -- delete -f deploymentFiles/filebeat/filebeatDeployment.yaml
    minikube kubectl -- delete -f deploymentFiles/filebeat/metricbeatDeployment.yaml

    minikube kubectl -- delete -f deploymentFiles/kibana/kibanaDeployment2.yaml
    minikube kubectl -- delete -f deploymentFiles/kibana/kibanaService2.yaml

    minikube kubectl -- delete -f deploymentFiles/filebeat/metricserverDeployment.yaml
    minikube kubectl -- delete -f deploymentFiles/filebeat/metricserverService.yaml

    minikube kubectl -- delete -n argocd-ns -f deploymentFiles/argoCD/argoDeployment.yaml
    minikube kubectl -- delete -n argocd-ns -f deploymentFiles/argoCD/argoService.yaml




    minikube kubectl -- delete -f deploymentFiles/curator/curator-cronjob.yaml

    ###(Do not Uncomment the following block, not tested TODO)
    # minikube kubectl -- delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    # minikube kubectl -- delete -f deploymentFiles/mongo/mongoAppDeployment.yaml

    ## Delete namespaces
    minikube kubectl -- delete -f deploymentFiles/namespaces/hellopyNamespace.yaml
    minikube kubectl -- delete -f deploymentFiles/namespaces/elasticNamespace.yaml
    minikube kubectl -- delete -f deploymentFiles/namespaces/logstashNamespace.yaml
    minikube kubectl -- delete -f deploymentFiles/namespaces/kibanaNamespace.yaml
    minikube kubectl -- delete -f deploymentFiles/namespaces/filebeatNamespace.yaml
    minikube kubectl -- delete -f deploymentFiles/namespaces/argoNamespace.yaml


fi


###
### Multinode restart
###
if [ $1 == '2noderestart' ]
then

    minikube delete
    # minikube config set vm-driver virtualbox
    minikube start --nodes 4
    # minikube addons enable metrics-server

fi


###
### Create Multinode Configuration
###
if [ $1 == '2nodestart' ]
then

    ## Creates multi node minikube deployment
    minikube config set memory 2000
    minikube config set cpus 2
    # minikube config set vm-driver virtualbox
    minikube start --nodes 4
    # minikube addons enable metrics-server

fi



##
## Create ceph cluster. (Did not fully work, required clean unpartitioned disk)
##
if [ $1 == '2nodesetup' ]
then
    cd apps/rook/cluster/examples/kubernetes/ceph

    minikube kubectl -- create -f crds.yaml
    minikube kubectl -- create -f common.yaml
    minikube kubectl -- create -f operator.yaml

    minikube kubectl -- -n rook-ceph create secret generic rook-ceph-crash-collector-keyring
    minikube kubectl -- create -f cluster.yaml
    cd ../../../../../..

fi

##
## Teardown multinode configuration
##
if [ $1 == '2nodeteardown' ]
then

    cd apps/rook/cluster/examples/kubernetes/ceph

    minikube kubectl -- delete -f crds.yaml
    minikube kubectl -- delete -f common.yaml
    minikube kubectl -- delete -f operator.yaml

    minikube kubectl -- -n rook-ceph delete secret generic rook-ceph-crash-collector-keyring
    minikube kubectl -- delete -f cluster.yaml

    cd ../../../../../..

fi
