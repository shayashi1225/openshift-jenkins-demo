if [ "$#" -ne 2 ]; then
    echo "Usage:"
    echo "  $0 GUID CICD_NameSpace"
    exit 1
fi

GUID=$1
CICD_NM=$2

echo "Creating Demo Projects for GUID=${GUID}"
#oc new-project ${GUID}-jenkins    --display-name="${GUID} AdvDev Homework Jenkins"
oc new-project ${GUID}-tasks-dev  --display-name="${GUID} AdvDev Homework Tasks Development"
oc new-project ${GUID}-tasks-prod --display-name="${GUID} AdvDev Homework Tasks Production"


echo "Setting up Tasks Development Environment in project ${GUID}-tasks-dev"
# Set up Dev Project
oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-tasks-dev

# Set up Dev Application
oc apply -f manifests/tasks-cm-dev.yaml -n ${GUID}-tasks-dev
#oc apply -f manifests/tasks-dc-dev.yaml -n ${GUID}-tasks-dev
sed s/GUID/${GUID}/g manifests/tasks-dc-dev.yaml | oc create -n ${GUID}-tasks-dev -f -
oc apply -f manifests/tasks-svc-dev.yaml -n ${GUID}-tasks-dev
oc apply -f manifests/tasks-route-dev.yaml -n ${GUID}-tasks-dev

# Set up Dev Build Config

#oc apply -f manifests/tasks-is-dev.yaml -n ${GUID}-tasks-dev
#oc apply -f manifests/tasks-bc-dev.yaml -n ${GUID}-tasks-dev
sed s/GUID/${GUID}/g manifests/tasks-is-dev.yaml | oc create -n ${GUID}-tasks-dev -f -
sed s/GUID/${GUID}/g manifests/tasks-bc-dev.yaml | oc create -n ${GUID}-tasks-dev -f -


echo "Setting up Tasks Production Environment in project ${GUID}-tasks-prod"

# Set up Production Project
oc policy add-role-to-group system:image-puller system:serviceaccounts:${GUID}-tasks-prod -n ${GUID}-tasks-dev
oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-tasks-prod

# Set up Blue Application
oc apply -f manifests/tasks-cm-blue.yaml -n ${GUID}-tasks-prod
#oc apply -f manifests/tasks-dc-blue.yaml -n ${GUID}-tasks-prod
sed s/GUID/${GUID}/g manifests/tasks-dc-blue.yaml | oc create -n ${GUID}-tasks-prod -f -
oc apply -f manifests/tasks-svc-blue.yaml -n ${GUID}-tasks-prod

# Set up Green Application
oc apply -f manifests/tasks-cm-green.yaml -n ${GUID}-tasks-prod
#oc apply -f manifests/tasks-dc-green.yaml -n ${GUID}-tasks-prod
sed s/GUID/${GUID}/g manifests/tasks-dc-green.yaml | oc create -n ${GUID}-tasks-prod -f -
oc apply -f manifests/tasks-svc-green.yaml -n ${GUID}-tasks-prod

# Expose Green service as route -> Force Green -> Blue deployment on first run
oc apply -f manifests/tasks-route-prod.yaml -n ${GUID}-tasks-prod

# Create Jenkins Agent
#oc new-build --strategy=docker -D $'FROM registry.access.redhat.com/ubi8/go-toolset:latest as builder\n
#ENV SKOPEO_VERSION=v1.0.0\n
#RUN git clone -b $SKOPEO_VERSION https://github.com/containers/skopeo.git && cd skopeo/ && make binary-local DISABLE_CGO=1\n
#FROM image-registry.openshift-image-registry.svc:5000/openshift/jenkins-agent-maven:v4.0 as final\n
#USER root\n
#RUN mkdir /etc/containers\n
#COPY --from=builder /opt/app-root/src/skopeo/default-policy.json /etc/containers/policy.json\n
#COPY --from=builder /opt/app-root/src/skopeo/skopeo /usr/bin\n
#USER 1001' --name=jenkins-agent-appdev -n ${CICD_NM}

#sed s/GUID-jenkins/${CICD_NM}/g manifests/agent-cm.yaml | oc create -n ${CICD_NM} -f -
NEXUS_PASSWORD=admin123
curl -o setup_nexus3.sh -s https://raw.githubusercontent.com/redhat-gpte-devopsautomation/ocp_advanced_development_resources/master/nexus/setup_nexus3.sh
chmod +x setup_nexus3.sh
./setup_nexus3.sh admin $NEXUS_PASSWORD http://$(oc get route nexus --template='{{ .spec.host }}' -n ${CICD_NM})
rm setup_nexus3.sh


# Regist source to Gogs repository
GOGS_SVC=$(oc get route gogs -o template --template='{{.spec.host}}' -n ${CICD_NM})
GOGS_USER=gogs
GOGS_PWD=gogs

cat <<EOF > /tmp/data.json
{
  "clone_addr": "https://github.com/shayashi1225/openshift-jenkins-demo.git",
  "uid": 1,
  "repo_name": "openshift-tasks-jenkinsfile"
}
EOF 

_RETURN=$(curl -o /tmp/curl.log -sL -w "%{http_code}" -H "Content-Type: application/json" \
-u $GOGS_USER:$GOGS_PWD -X POST http://$GOGS_SVC/api/v1/repos/migrate -d @/tmp/data.json)

if [ $_RETURN != "201" ] ;then
  echo "ERROR: Failed to import openshift-tasks GitHub repo"
  cat /tmp/curl.log
  exit 255
fi

