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
