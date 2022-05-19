#!/bin/bash

OPTIONS=${1:-INSTALL}

IGREEN='\033[0;92m'
COLOR_OFF='\033[0m' 
BRED='\033[1;31m' 
ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
S3_SERVICE_ACCOUNT=s3-access-sa
ECR_REPOSITORY=eks-workshop-demo/test-detail
APP_VERSION=1.0
ADDRESS=https://$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

exit_trap () {
  local lc="$BASH_COMMAND" rc=$?
  echo "Command [$lc] exited with code [$rc]"
}

trap exit_trap EXIT

usage() {
    
    filename=$(basename $BASH_SOURCE)
    printf "${BRED} ./${filename} # to install spinnaker ${COLOR_OFF}\n"
    printf "${BRED} ./${filename} DELETE # to clean up this chapter ${COLOR_OFF}\n "
}

installing_yq() { # INSTALLING yq Locally

echo "+++++++++++++++++++++++++++++++++++++++++++++++"
printf "${IGREEN}installing yq locally${COLOR_OFF}\n"
echo "+++++++++++++++++++++++++++++++++++++++++++++++"

VERSION="v4.25.1"
BINARY="yq_linux_amd64"


wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - |\
  tar xz && sudo mv ${BINARY} /usr/bin/yq
  
if [ $? != 0 ]; then
    
    printf "${BRED}Yq is not installed, Make sure Version of Yq is correct"
    exit
fi

}


config() { # GET User Input
    
    printf "${BRED}Spinnaker Operator Version and Spinnaker Release Version should be like 1.2.5 1.26.6 NOT LIKE v1.2.5${COLOR_OFF}\n"
    
    read -p "Spinaker operator Version from https://github.com/armory/spinnaker-operator/releases for versions : " SPINNAKER_OPERATOR_VERSION
    
    read -p "Spinnaker release from https://spinnaker.io/community/releases/versions/:  " SPINNAKER_VERSION
    
    read -p "Git hub account user name: " GITHUB_USER
    
    read -p "Git hub token: " -s GITHUB_TOKEN
    
    if [[ ${SPINNAKER_OPERATOR_VERSION} =~ ^[vV]  || ${SPINNAKER_VERSION} =~ ^[vV] ]]; then
        
        printf "\n${BRED}Version Number should only have Numbers ${COLOR_OFF} \n"
        exit
    fi
    
    echo " 

UserInput
**********************************************************
ACCOUNT_ID: ${ACCOUNT_ID}
AWS_REGION: ${AWS_REGION}
SPINNAKER_OPERATOR_VERSION: ${SPINNAKER_OPERATOR_VERSION}
SPINNAKER_VERSION: ${SPINNAKER_VERSION}
GITHUB_USER: ${GITHUB_USER}
***********************************************************   
"
}

install_spinnaker_creds() { # ISTALLING Spinnaker Creds
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}INSTALLING Spinnaker CRDs${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    eksctl utils associate-iam-oidc-provider --region=${AWS_REGION} --cluster=eksworkshop-eksctl --approve
    cd ~/environment
    mkdir -p spinnaker-operator && cd spinnaker-operator
    bash -c "curl -L https://github.com/armory/spinnaker-operator/releases/download/v${SPINNAKER_OPERATOR_VERSION}/manifests.tgz | tar -xz"
    kubectl apply -f deploy/crds/
}

install_spinnaker_operator(){ # INSTALLING Spinaker Operator
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}INSTALLING Spinnaker Operator${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    cd ~/environment/spinnaker-operator
    kubectl create ns spinnaker-operator
    kubectl -n spinnaker-operator apply -f deploy/operator/cluster
    
    echo "Waiting for pods to come up, It takes 2-3 Mins"
    sleep 30
    PODS_RUNNING="false"
    total_time=30
    while [ ${PODS_RUNNING} == "false" ]; do
        first_field=$(kubectl get pod -n spinnaker-operator|grep -i spinnaker-op|awk '{print $2}'|cut -d "/" -f1)
        second_field=$(kubectl get pod -n spinnaker-operator|grep -i spinnaker-op|awk '{print $2}'|cut -d "/" -f2)
        status=$(kubectl get pod -n spinnaker-operator|grep -i spinnaker-op|awk '{print $3}')
        sleep 10
    	echo "Checking if pods are running"
        if [ ${first_field} == ${second_field} ] && [ ${status} == "Running" ]; then 
               	echo "Pods are running"
               	PODS_RUNNING="true"
        else
        	echo "Waiting for pods to come up"
        fi	
        total_time=`expr ${total_time} + 10`
        if [ ${total_time} -gt 200 ]; then
            printf "${BRED}Something is wrong, Pods don't take this much time${COLOR_OFF}\n"
            printf "${BRED}Check if the Version number is correct${COLOR_OFF}\n"
            exit
        fi
    done
    
    
    kubectl get pod -n spinnaker-operator
}

create_s3() { # CREATING S3 Bucket
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}CREATING S3 Bucket${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    
    export S3_BUCKET=spinnaker-workshop-$(cat /dev/urandom | LC_ALL=C tr -dc "[:alpha:]" | tr '[:upper:]' '[:lower:]' | head -c 10)
    aws s3api head-bucket --bucket ${S3_BUCKET} >/dev/null 2>&1
    if [[ $? != 0  ]]; then
        
        printf "Bucket Doesnot Exists Creating one \n"
        aws s3 mb s3://${S3_BUCKET}
    
        aws s3api put-public-access-block \
        --bucket ${S3_BUCKET} \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        echo "S3 Bucket Name: ${S3_BUCKET}"
        echo "S3_BUCKET_NAME=${S3_BUCKET}" > /tmp/tempconfig.log
    else
        printf "Bucket ${S3_BUCKET} already exits choose another name"
        exit
    fi

}


create_iam_service_account() { # CREATING Service Account
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}CREATING Service Account${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    
    kubectl create ns spinnaker
    cluster_name=$(eksctl get cluster|grep -i eksworkshop|awk '{print $1}')
    if [ -z "${cluster_name}" ]
    then
        printf "${BRED}Cluster Doesnot Exists${COLOR_OFF}\n"
        printf "${IGREEN}Open New Terminal to Run Script${COLOR_OFF}\n"
        exit;
    else
        printf "${IGREEN}ClusterName: ${cluster_name}${COLOR_OFF}\n"
    fi
    
    sleep 5
    
    eksctl create iamserviceaccount \
    --name s3-access-sa \
    --namespace spinnaker \
    --cluster ${cluster_name} \
    --attach-policy-arn arn\:aws\:iam::aws\:policy/AmazonS3FullAccess \
    --approve \
    --override-existing-serviceaccounts

    echo "S3 service account is ${S3_SERVICE_ACCOUNT}"
    
    echo "Describing Service Account"
    
    kubectl describe sa s3-access-sa -n spinnaker
    
    sleep 3

}


create_ecr_repository() { # CREATING ECR Repository 
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}CREATING ECR Repository${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    
    
    cd ~/environment/eks-app-mesh-polyglot-demo/workshop
    export ECR_REPOSITORY=eks-workshop-demo/test-detail
    export APP_VERSION=1.0
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    aws ecr describe-repositories --repository-name $ECR_REPOSITORY >/dev/null 2>&1
    if [ $? != 0 ]; then
        aws ecr create-repository --repository-name $ECR_REPOSITORY >/dev/null
    fi
    echo "ECR_REPOSITORY_NAME=${ECR_REPOSITORY}" > /tmp/tempconfig.log
    TARGET=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$APP_VERSION
    docker build -t $TARGET apps/catalog_detail
    docker push $TARGET
}


create_config_map() { # CREATING Config Map
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}CREATING Config Map${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    

    cd ~/environment
    
    cat << EOF > config.yaml
    interval: 30m # defines refresh interval
    registries: # list of registries to refresh
      - registryId: "$ACCOUNT_ID"
        region: "$AWS_REGION"
        passwordFile: "/etc/passwords/my-ecr-registry.pass"
EOF
    
    kubectl -n spinnaker create configmap token-refresh-config --from-file config.yaml

    echo "Checking Config Map"
    kubectl describe configmap token-refresh-config -n spinnaker
    sleep 5

}


download_spinnaker_tool() { # DOWNLOAD and BUILD Spinnaker Tool
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}DOWNLOADING Spinnaker Tool${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    
    cd ~/environment
    git clone https://github.com/armory/spinnaker-tools.git
    cd spinnaker-tools
    go mod download all
    go build

}


create_service_account() { # CREATING Service Account
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}CREATING Service Account${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    
    export CONTEXT=$(kubectl config current-context)
    export SOURCE_KUBECONFIG=${HOME}/.kube/config
    export SPINNAKER_NAMESPACE="spinnaker"
    export SPINNAKER_SERVICE_ACCOUNT_NAME="spinnaker-ws-sa"
    export DEST_KUBECONFIG=${HOME}/Kubeconfig-ws-sa
    
    echo $CONTEXT
    echo $SOURCE_KUBECONFIG
    echo $SPINNAKER_NAMESPACE
    echo $SPINNAKER_SERVICE_ACCOUNT_NAME
    echo $DEST_KUBECONFIG
    sleep 10
    cd ~/environment/spinnaker-tools
    ./spinnaker-tools create-service-account   --kubeconfig ${SOURCE_KUBECONFIG}   --context ${CONTEXT}   --output ${DEST_KUBECONFIG}   --namespace ${SPINNAKER_NAMESPACE}   --service-account-name ${SPINNAKER_SERVICE_ACCOUNT_NAME}


}

modify_spinnakerservice_file() { # CREATING  Manifest File For Spinnaker Service
    
    echo "+++++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}CREATING Minifest File for Spinnaker Service${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++++"
    sleep 5
    
    cd ~/environment/spinnaker-operator
    cp ~/environment/eks-app-mesh-polyglot-demo/workshop/spinnaker/spinnakerservice.yml deploy/spinnaker/basic/spinnakerservice.yml
    SPINNAKER_VERSION=${SPINNAKER_VERSION} yq  -i '.spec.spinnakerConfig.config.version = env(SPINNAKER_VERSION)' deploy/spinnaker/basic/spinnakerservice.yml 
    S3_BUCKET_NAME=${S3_BUCKET} yq  -i '.spec.spinnakerConfig.config.persistentStorage.s3.bucket = env(S3_BUCKET_NAME)' deploy/spinnaker/basic/spinnakerservice.yml
    AWS_REGION=${AWS_REGION} yq  -i '.spec.spinnakerConfig.config.persistentStorage.s3.region = env(AWS_REGION)' deploy/spinnaker/basic/spinnakerservice.yml
    GITHUB_USER=${GITHUB_USER} yq  -i '.spec.spinnakerConfig.config.artifacts.github.accounts[0].name = env(GITHUB_USER)' deploy/spinnaker/basic/spinnakerservice.yml
    GITHUB_TOKEN=${GITHUB_TOKEN} yq  -i '.spec.spinnakerConfig.config.artifacts.github.accounts[0].token = env(GITHUB_TOKEN)' deploy/spinnaker/basic/spinnakerservice.yml
    ECR_REPOSITORY=${ECR_REPOSITORY} yq -i '.spec.spinnakerConfig.profiles.clouddriver.dockerRegistry.accounts[0].repositories[0] = env(ECR_REPOSITORY)' deploy/spinnaker/basic/spinnakerservice.yml
    ADDRESS=${ADDRESS} yq -i '.spec.spinnakerConfig.profiles.clouddriver.dockerRegistry.accounts[0].address = env(ADDRESS)' deploy/spinnaker/basic/spinnakerservice.yml
    S3_SERVICE_ACCOUNT=${S3_SERVICE_ACCOUNT} yq -i '.spec.spinnakerConfig.service-settings.front50.kubernetes.serviceAccountName = env(S3_SERVICE_ACCOUNT)' deploy/spinnaker/basic/spinnakerservice.yml
    cp ${HOME}/Kubeconfig-ws-sa ~/environment/eks-app-mesh-polyglot-demo/workshop/spinnaker/test.yml
    yq eval-all -I 4 'select(fileIndex==0).spec.spinnakerConfig.files.kubeconfig-sp = select(fileIndex==1) | select(fileIndex==0)' -i  deploy/spinnaker/basic/spinnakerservice.yml ~/environment/eks-app-mesh-polyglot-demo/workshop/spinnaker/test.yml  
    sed -i "s/kubeconfig-sp:/kubeconfig-sp: |/g" deploy/spinnaker/basic/spinnakerservice.yml
    rm ~/environment/eks-app-mesh-polyglot-demo/workshop/spinnaker/test.yml
}


install_spinnaker_service() { # INSTALLING Spinnaker Service
    
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}INSTALLING Spinnaker service using below values${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    
    echo "Account_ID: ${ACCOUNT_ID}"
    echo "AWS_REGION: ${AWS_REGION}"
    echo "SPINNAKER_VERSION: ${SPINNAKER_VERSION}"
    echo "GITHUB_USER: ${GITHUB_USER}"
    echo "S3_BUCKET: ${S3_BUCKET}"
    echo "S3_SERVICE_ACCOUNT: ${S3_SERVICE_ACCOUNT}"
    echo "ECR_REPOSITORY: ${ECR_REPOSITORY}"
    echo "++++++++++++++++++++++++++++++++++++++++++++"
    sleep 10
    
    cd ~/environment/spinnaker-operator/
    kubectl -n spinnaker apply -f deploy/spinnaker/basic/spinnakerservice.yml
    echo "==================================================================================="
    printf "${IGREEN}Run Commands to Check Status of Pods and Services, It could take 5 Mins${COLOR_OFF}\n"
    printf "${IGREEN}Get all the resources created${COLOR_OFF}\n"
    printf "kubectl get svc,pod -n spinnaker\n"
    printf "${IGREEN}Watch the install progress${COLOR_OFF}\n"
    printf "kubectl -n spinnaker get spinsvc spinnaker -w\n"
}


install_spinnaker() { # CALLING ALL THE FUNCTIONS
    START_TIME=$(date +%s)
    installing_yq
    install_spinnaker_creds
    install_spinnaker_operator
    create_s3
    create_iam_service_account
    create_ecr_repository
    create_config_map
    download_spinnaker_tool
    create_service_account
    modify_spinnakerservice_file
    install_spinnaker_service
    END_TIME=$(date +%s)
    ELAPSED=$(( END_TIME - START_TIME ))
    ((hour=${ELAPSED}/3600))
    ((mins=(${ELAPSED}-hour*3600)/60))
    ((sec=${ELAPSED}-((hour*3600) + (mins*60))))
    printf "TIME TAKEN: ${IGreen} %02d:%02d:%02d\n" "$hour" "$mins" "$sec"
}


clean_up() { #DELETE THE RESOURCES

    for i in $(kubectl get crd | grep spinnaker | cut -d" " -f1) ; do
        kubectl delete crd $i
    done
    
    
    cluster_name=$(eksctl get cluster|grep -i eksworkshop|awk '{print $1}')
    
    
    eksctl delete iamserviceaccount \
    --name s3-access-sa \
    --namespace spinnaker \
    --cluster ${cluster_name} 
    
    for namespace in $(kubectl get ns |grep -i spinnaker|awk '{print $1}'); do
        printf "${IGREEN}Deleting Namespace ${namespace} ${COLOR_OFF}\n"
        kubectl delete ns ${namespace}
    done
    
    
    cd ~/environment
    if [ -f config.yaml ]; then
        printf "${IGREEN}Deleting file config.yaml${COLOR_OFF}\n"
        rm config.yaml
    fi
    
    if [ -d spinnaker-tools ]; then 
        printf "${IGREEN}Deleting Spinnaker-tools Folder ${COLOR_OFF}\n"
        rm -rf spinnaker-tools
    fi 
    
    if [ -d spinnaker-operator ]; then 
        printf "${IGREEN}Deleting Spinnaker-operator Folder ${COLOR_OFF}\n"
        rm -rf spinnaker-operator
    fi 
    
    if [ -f /tmp/tempconfig.log ]; then
    
        BUCKET_NAME=$(cat /tmp/tempconfig.log|grep -i S3_BUCKET_NAME| cut -d "=" -f2)
        aws s3api head-bucket --bucket ${S3_BUCKET} >/dev/null 2>&1
        if [ $? = 0 ]; then
            printf "${IGREEN}Deleting S3 Bucket: ${BUCKET_NAME}${COLOR_OFF}\n"
            aws s3 rb s3://${BUCKET_NAME} --force  
        else
            printf "${IGREEN}S3 Bucket ${BUCKET_NAME} already deleted${COLOR_OFF}\n"
        fi
       
        printf "Delete ECR Repository \n"
        
        ECR_REPOSITORY_NAME=$(cat /tmp/tempconfig.log|grep -i ECR_REPOSITORY_NAME| cut -d "=" -f2)
         aws ecr describe-repositories --repository-name $ECR_REPOSITORY >/dev/null 2>&1
       
        if [ $? = 0 ]; then
            
            printf "${IGREEN}Deleting ECR Repository: ${ECR_REPOSITORY_NAME}${COLOR_OFF}\n"
            aws ecr delete-repository --repository-name ${ECR_REPOSITORY_NAME} --force
           
        else
            printf "${IGREEN}ECR Repository already deleted${COLOR_OFF}\n"
        fi
        rm /tmp/tempconfig.log
    fi
    
    trap - EXIT
    echo "++++++++++++++++++++++++++++++++++++++++++++"
    printf "${IGREEN}Clean UP Completed${COLOR_OFF}\n"


    
}


if [[ ${OPTIONS} == "INSTALL" ]]; then
    while true; do
        config
        read -p "All information correct y/n:" yn
        case $yn in
            [Yy]* ) install_spinnaker; break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done

elif [[ ${OPTIONS} == "DELETE" ]]; then
    #statements
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    printf "${BRED}DELETING RESOURCES ${COLOR_OFF}\n"
    echo "+++++++++++++++++++++++++++++++++++++++++++"
    clean_up
else
    usage
    
fi