#!/bin/bash

# **************** Global variables
source ./.env

export HELM_RELEASE_NAME=watson-stt-kubernetes
export HELM_CHART_NAME=watson-stt-kubernetes
export DEFAULT_NAMESPACE="default"

# **********************************************************************************
# Functions definition
# **********************************************************************************

function loginIBMCloud () {
    
    echo ""
    echo "*********************"
    echo "loginIBMCloud"
    echo "*********************"
    echo ""

    ibmcloud login --apikey $IC_API_KEY
    ibmcloud target -r $REGION
    ibmcloud target -g $GROUP
}

function connectToCluster () {

    echo ""
    echo "*********************"
    echo "connectToCluster"
    echo "*********************"
    echo ""

    ibmcloud ks cluster config -c $CLUSTER_ID
}

function createDockerCustomConfigFile () {

    echo ""
    echo "*********************"
    echo "createDockerCustomConfigFile"
    echo "*********************"
    echo ""

    sed "s+IBM_ENTITLEMENT_KEY+$IBM_ENTITLEMENT_KEY+g;s+IBM_ENTITLEMENT_EMAIL+$IBM_ENTITLEMENT_EMAIL+g" "$(pwd)/custom_config.json_template" > "$(pwd)/custom_config.json"
    IBM_ENTITLEMENT_SECRET=$(base64 -i "$(pwd)/custom_config.json")
    echo "IBM_ENTITLEMENT_SECRET: $IBM_ENTITLEMENT_SECRET"

    sed "s+IBM_ENTITLEMENT_SECRET+$IBM_ENTITLEMENT_SECRET+g" $(pwd)/charts/$HELM_CHART_NAME/values.yaml_template > $(pwd)/charts/$HELM_CHART_NAME/values.yaml
    cat $(pwd)/charts/$HELM_CHART_NAME/values.yaml
}

function installHelmChart () {

    echo ""
    echo "*********************"
    echo "installHelmChart"
    echo "*********************"
    echo ""

    TEMP_PATH_ROOT=$(pwd)
    cd $TEMP_PATH_ROOT/charts
    
    helm dependency update ./$HELM_CHART_NAME/
    helm install --dry-run --debug helm-test ./$HELM_CHART_NAME/

    helm lint $HELM_RELEASE_NAME ./$HELM_CHART_NAME/
    helm install $HELM_RELEASE_NAME ./$HELM_CHART_NAME/

    verifyDeploment
    verifyPod
        
    cd $TEMP_PATH_ROOT
}

function uninstallHelmChart () {

    echo ""
    echo "*********************"
    echo "uninstallHelmChart"
    echo "*********************"
    echo ""

    TEMP_PATH_ROOT=$(pwd)
    cd $TEMP_PATH_ROOT/charts

    helm uninstall $HELM_CHART_NAME

    cd $TEMP_PATH_ROOT
}

function verifyWatsonSTTContainer () {
    
    echo ""
    echo "*********************"
    echo "verifyWatsonSTTContainer"
    echo "*********************"
    echo ""

    echo "* Download audio"
    export FIND="ibm-watson-stt-embed"
    POD=$(kubectl get pods -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $1;}')
    echo "Pod: $POD"
    export RUNTIME_CONTAINER="runtime"
    RESULT=$(kubectl exec --stdin --tty $POD --container $RUNTIME_CONTAINER -n $DEFAULT_NAMESPACE -- curl -sLo example.flac https://github.com/watson-developer-cloud/doc-tutorial-downloads/raw/master/speech-to-text/0001.flac)
    RESULT=$(kubectl exec --stdin --tty $POD --container $RUNTIME_CONTAINER -n $DEFAULT_NAMESPACE -- ls | grep 'example')
    echo ""
    echo "Result of download the example audio:"
    echo ""
    echo "$RESULT"
    echo ""
    echo "* Invocation of REST API audio"
    echo "Result of the Watson STT REST API invocation:"
    POD=$(kubectl get pods -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $1;}')
    echo "Pod: $POD"
    export RUNTIME_CONTAINER="runtime"
    RESULT=$(kubectl exec --stdin --tty $POD -n $DEFAULT_NAMESPACE --container $RUNTIME_CONTAINER --  curl "http://localhost:1080/speech-to-text/api/v1/recognize" --header "Content-Type: audio/flac"  --data-binary @example.flac)
    echo ""
    echo "Result of download the example audio:"
    echo ""
    echo "http://localhost:1080/speech-to-text/api/v1/recognize"
    echo ""
    echo "$RESULT"
    echo ""


    echo "Verify the running pod on your cluster."
    kubectl get pods -n $DEFAULT_NAMESPACE
    echo "Verify in the deployment in the Kubernetes dashboard."
    echo ""
    open "https://cloud.ibm.com/kubernetes/clusters/$CLUSTER_ID/overview"
    echo ""

    read ANY_VALUE
}

function verifyWatsonSTTLoadbalancer () {

    echo ""
    echo "*********************"
    echo "verifyWatsonSTTLoadbalancer"
    echo "this could take up to 10 min"
    echo "*********************"
    echo ""

    verifyLoadbalancer

    SERVICE=watson-stt-container-vpc-nlb
    EXTERNAL_IP=$(kubectl get svc $SERVICE | grep  $SERVICE | awk '{print $4;}')
    echo "EXTERNAL_IP: $EXTERNAL_IP"
    echo "Verify invocation of Watson STT API from the local machine:"
    curl -sLo example.flac https://github.com/watson-developer-cloud/doc-tutorial-downloads/raw/master/speech-to-text/0001.flac
    curl "http://$EXTERNAL_IP:1080/speech-to-text/api/v1/recognize" \
        --header "Content-Type: audio/flac" \
        --data-binary @example.flac
}

# ************ functions used internal **************


function verifyLoadbalancer () {

    echo ""
    echo "*********************"
    echo "verifyLoadbalancer"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=("watson-stt-container-vpc-nlb")
    export STATUS_SUCCESS=""
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for $i: ($j) from max retrys ($max_retrys)"
            j=0
            export FIND=$i
            while :
            do      
            ((j++))
            STATUS_CHECK=$(kubectl get svc $FIND -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $4;}')
            echo "Status: $STATUS_CHECK"
            if ([ "$STATUS_CHECK" != "$STATUS_SUCCESS" ] && [ "$STATUS_CHECK" != "<pending>" ]); then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created ($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 60
            done
        done
}

function verifyDeploment () {

    echo ""
    echo "*********************"
    echo "verifyDeploment"
    echo "*********************"
    echo ""

    export max_retrys=4
    j=0
    array=("ibm-watson-stt-embed")
    export STATUS_SUCCESS="ibm-watson-stt-embed"
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for ($i)"
            j=0
            export FIND=$i
            while :
            do      
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get deployment $FIND -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $1;}')
            echo "Status: $STATUS_CHECK"
            if [ "$STATUS_CHECK" = "$STATUS_SUCCESS" ]; then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 10
            done
        done
}

function verifyPod () {

    echo ""
    echo "*********************"
    echo "verifyPod could take 10 min"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=("ibm-watson-stt-embed")
    export STATUS_SUCCESS="1/1"
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for ($i)"
            j=0
            export FIND=$i
            while :
            do     
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get pods -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $2;}')
            echo "Status: $STATUS_CHECK"
            if [ "$STATUS_CHECK" = "$STATUS_SUCCESS" ]; then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 60
            done
        done
}


#**********************************************************************************
# Execution
# *********************************************************************************

loginIBMCloud

connectToCluster

createDockerCustomConfigFile

installHelmChart

verifyWatsonSTTContainer

verifyWatsonSTTLoadbalancer

uninstallHelmChart
