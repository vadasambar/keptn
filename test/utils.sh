#!/bin/bash

function timestamp() {
  date +"[%Y-%m-%d %H:%M:%S]"
}

function print_error() {
  echo "::error file=${BASH_SOURCE[1]##*/},line=${BASH_LINENO[0]}::$(timestamp) ${*}"
}

function auth_at_keptn() {
  ENDPOINT=$1
  API_TOKEN=$2
  RETRY=0
  RETRY_MAX=5

  echo "Authenticating at $ENDPOINT"
  while [[ $RETRY -lt $RETRY_MAX ]]; do
    keptn auth --endpoint="$ENDPOINT" --api-token="$API_TOKEN"

    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]]; then
      echo "Successfully authenticated at Keptn API!"
      break
    else
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 10s ..."
      sleep 10
    fi
  done

  if [[ "$RETRY" == "$RETRY_MAX" ]]; then
    print_error "Authentication at $ENDPOINT unsuccessful"
    exit 1
  fi
}

function trigger_evaluation_request() {
  PROJECT=$1
  STAGE=$2
  SERVICE=$3

  response=$(keptn trigger evaluation --project="$PROJECT" --stage="$STAGE" --service="$SERVICE" --timeframe=5m 2>&1)

  echo "$response"
}

function trigger_evaluation() {
  PROJECT=$1
  STAGE=$2
  SERVICE=$3

  response=$(keptn trigger evaluation --project="$PROJECT" --stage="$STAGE" --service="$SERVICE" --timeframe=5m)
  keptn_context_id=$(echo "$response" | awk -F'Keptn context:' '{ print $2 }' | xargs)

  echo "$keptn_context_id"
}

function get_evaluation_finished_event() {
  keptn_context_id=$1
  keptn get event evaluation.finished --keptn-context="${keptn_context_id}" 2>/dev/null | tail -n +5
}

function get_event() {
  event_type=$1
  keptn_context_id=$2
  project=$3
  keptn get event "$event_type" --keptn-context="${keptn_context_id}" --project="$project" --quiet
}

function get_event_with_retry() {
  event_type=$1
  keptn_context_id=$2
  project=$3

  RETRY=0; RETRY_MAX=50;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    response=$(keptn get event "$event_type" --keptn-context="${keptn_context_id}" --project="$project" --quiet)

    if [[ "$response" == "No event returned" ]]; then
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 10s for ${event_type} event..." >&2
      sleep 10
    else
      echo "$response"
      break
    fi
  done

  if [[ "$RETRY" == "$RETRY_MAX" ]]; then
    print_error "URL ${URL} could not be reached"
    exit 1
  fi

}

function send_approval_triggered_event() {
  PROJECT=$1
  STAGE=$2
  SERVICE=$3
  RESULT=$4
  TYPE="sh.keptn.event.${STAGE}.approval.triggered"

  jq -r \
      --arg type "$TYPE" \
      --arg project "$PROJECT" \
      --arg stage "$STAGE" \
      --arg service "$SERVICE" \
      --arg result "$RESULT" \
      '.type=$type | .data.project=$project | .data.stage=$stage | .data.service=$service | .data.result=$result' \
      ./test/assets/approval_triggered_event_template.json > tmp_approval_triggered_event.json

  response=$(keptn send event --file=tmp_approval_triggered_event.json)
  rm tmp_approval_triggered_event.json

  keptn_context_id=$(echo "$response" | awk -F'Keptn context:' '{ print $2 }' | xargs)
  echo "$keptn_context_id"
}

function send_evaluation_invalidated_event() {
  PROJECT=$1
  STAGE=$2
  SERVICE=$3
  TRIGGERED_ID=$4
  KEPTN_CONTEXT=$5

  jq -r \
    --arg project "$PROJECT" \
    --arg stage "$STAGE" \
    --arg service "$SERVICE" \
    --arg triggered_id "$TRIGGERED_ID" \
    --arg keptn_context "$KEPTN_CONTEXT" \
    '.data.project=$project | .data.stage=$stage | .data.service=$service | .triggeredid=$triggered_id | .shkeptncontext=$keptn_context' \
    ./test/assets/evaluation_invalidated_event_template.json > tmp_evaluation_invalidated_event.json

  response=$(keptn send event --file=tmp_evaluation_invalidated_event.json)
  rm tmp_evaluation_invalidated_event.json

  keptn_context_id=$(echo "$response" | awk -F'Keptn context:' '{ print $2 }' | xargs)
  echo "$keptn_context_id"
}

function send_event_json() {
  EVENT_JSON_FILE_URI=$1

  response=$(keptn send event --file="$EVENT_JSON_FILE_URI")
  keptn_context_id=$(echo "$response" | awk -F'Keptn context:' '{ print $2 }' | xargs)
  echo "$keptn_context_id"
}

function get_keptn_event() {
  PROJECT=$1
  keptn_context_id=$2
  type=$3
  KEPTN_ENDPOINT=$4
  KEPTN_API_TOKEN=$5
  curl -X GET "${KEPTN_ENDPOINT}/mongodb-datastore/event?project=${PROJECT}&type=${type}&keptnContext=${keptn_context_id}" -H  "accept: application/json" -H  "x-token: ${KEPTN_API_TOKEN}" -k 2>/dev/null | jq -r '.events[0]'
}

function check_no_open_approvals() {
  PROJECT=$1
  STAGE=$2

  result=$(keptn get event approval.triggered --project="$PROJECT" --stage="$STAGE" | awk '{if(NR>1)print}')
  if [[ "$result" != "No approval.triggered events have been found" ]]; then
    echo "Received ${result} approval.triggered events but expected 0"
    exit 2
  else
    echo "Verified that there is no approval.triggered event"
  fi
}

function check_number_open_approvals() {
  PROJECT=$1
  STAGE=$2
  EXPECTED=$3

  approvalEvents=$(keptn get event approval.triggered --project="$PROJECT" --stage="$STAGE" | awk '{if(NR>1)print}')
  type=$(echo "$approvalEvents" | jq -r 'type')

  if [[ "$approvalEvents" == "No approval.triggered events have been found" ]]; then
    RESULT=0
  elif [ "$type" != "array"  ]; then
    RESULT=1
  else
    RESULT=$(echo "$approvalEvents" | jq -r 'length')
  fi

  if [[ "$RESULT" != "$EXPECTED" ]]; then
    echo "Received unexpected number of approval.triggered events: ${EXPECTED} (expected) = ${RESULT} (actual)"
    exit 2
  else
    echo "Verified number of approval.triggered events: ${EXPECTED} (expected) = ${RESULT} (actual)"
  fi
}

function verify_using_jq() {
  payload=$1
  attribute=$2
  expected=$3

  actual=$(echo "${payload}" | jq -r "${attribute}")

  if [[ "${actual}" != "${expected}" ]]; then
    print_error "ERROR: Checking $attribute, expected '${expected}', got '${actual}' ❌"
    exit 1
  else
    echo "Checking $attribute: ${actual} ✓"
  fi

  return 0
}

function verify_value() {
  attribute=$1
  actual=$2
  expected=$3

  if [[ "${actual}" != "${expected}" ]]; then
    print_error "ERROR: Checking $attribute, expected '${expected}', got '${actual}' ❌"
    exit 1
  else
    echo "Checking $attribute: ${actual} ✓"
  fi

  return 0
}

function verify_not_equal() {
  first=$1
  second=$2

  if [[ "${first}" != "${second}" ]]; then
    echo "Checking ${first} not equal ${second} ✓"
  else
    print_error "ERROR: Checking ${first} not equal ${second} ❌"
  fi
}

function verify_event_not_null() {
  if [[ $1 == "null" ]]; then
    # shellcheck disable=SC2152
    return -1
  fi
}

function verify_test_step() {
  if [[ $1 != '0' ]]; then
    print_error "$2"
    print_error "Keptn test step failed"
    exit 1
  fi
}

function wait_for_url() {
  URL=$1
  RETRY=0; RETRY_MAX=40;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    curl "$URL" -k

    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]]; then
      echo "Verified access to ${URL}"
      break
    else
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 10s for URL ${URL} ..."
      sleep 10
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "URL ${URL} could not be reached"
    exit 1
  fi
}

function verify_image_of_deployment() {
  DEPLOYMENT=$1; NAMESPACE=$2; IMAGE_NAME=$3;

  CURRENT_IMAGE_NAME=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o=jsonpath='{$.spec.template.spec.containers[:1].image}')

  if [[ "$CURRENT_IMAGE_NAME" == "$IMAGE_NAME" ]]; then
    echo "Found image ${CURRENT_IMAGE_NAME} in deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
  else
    print_error "ERROR: Found image ${CURRENT_IMAGE_NAME} but expected ${IMAGE_NAME}  in deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
    exit 1
  fi
}

# check if a deployment exists (does not need to be running)
function wait_and_check_if_deployment_exists() {
  DEPLOYMENT=$1; NAMESPACE=$2;
  RETRY=0; RETRY_MAX=40;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    DEPLOYMENT_LIST=$(eval "kubectl get deployments -n ${NAMESPACE} | awk '/$DEPLOYMENT /'" | awk '{print $1}') # list of multiple deployments when starting with the same name
    if [[ -z "$DEPLOYMENT_LIST" ]]; then
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Deployment not found - waiting 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
      sleep 15
    else
      echo "Found deployment ${DEPLOYMENT} in namespace ${NAMESPACE}: ${DEPLOYMENT_LIST}"
      break
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
    exit 1
  fi
}

# wait for a deployment to be up and running
function wait_for_deployment_in_namespace() {
  DEPLOYMENT=$1; NAMESPACE=$2;
  RETRY=0; RETRY_MAX=40;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    DEPLOYMENT_LIST=$(eval "kubectl get deployments -n ${NAMESPACE} | awk '/$DEPLOYMENT /'" | awk '{print $1}') # list of multiple deployments when starting with the same name
    if [[ -z "$DEPLOYMENT_LIST" ]]; then
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Deployment not found - waiting 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
      sleep 15
    else
      READY_REPLICAS=$(eval kubectl get deployments "$DEPLOYMENT" -n "$NAMESPACE" -o=jsonpath='{$.status.availableReplicas}')
      WANTED_REPLICAS=$(eval kubectl get deployments "$DEPLOYMENT"  -n "$NAMESPACE" -o=jsonpath='{$.spec.replicas}')
      UNAVAILABLE_REPLICAS=$(eval kubectl get deployments "$DEPLOYMENT"  -n "$NAMESPACE" -o=jsonpath='{$.status.unavailableReplicas}')
      if [[ "$READY_REPLICAS" = "$WANTED_REPLICAS" && "$UNAVAILABLE_REPLICAS" = "" ]]; then
        echo "Found deployment ${DEPLOYMENT} in namespace ${NAMESPACE}: ${DEPLOYMENT_LIST}"
        break
      else
          RETRY=$((RETRY+1))
          echo "Retry: ${RETRY}/${RETRY_MAX} - Unsufficient replicas for deployment - waiting 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
          sleep 15
      fi
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
    exit 1
  fi
}

function wait_for_deployment_with_image_in_namespace() {
  DEPLOYMENT=$1; NAMESPACE=$2;  IMAGE=$3
  RETRY=0; RETRY_MAX=40;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    DEPLOYMENT_IMAGE=$(eval kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o=jsonpath='{$.spec.template.spec.containers[:1].image}' --ignore-not-found)
    if [[ "$IMAGE" != "$DEPLOYMENT_IMAGE" ]]; then
        RETRY=$((RETRY+1))
        echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
        sleep 15
    else
        READY_REPLICAS=$(eval kubectl get deployments "$DEPLOYMENT" -n "$NAMESPACE" -o=jsonpath='{$.status.availableReplicas}')
        WANTED_REPLICAS=$(eval kubectl get deployments "$DEPLOYMENT"  -n "$NAMESPACE" -o=jsonpath='{$.spec.replicas}')
        if [[ "$READY_REPLICAS" = "$WANTED_REPLICAS" ]]; then
          echo "Found deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
          break
        else
          RETRY=$((RETRY+1))
          echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
          sleep 15
        fi
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
    exit 1
  fi
}

function wait_for_pod_number_in_deployment_in_namespace() {
  DEPLOYMENT=$1; POD_COUNT=$2; NAMESPACE=$3;
  RETRY=0; RETRY_MAX=40;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    DEPLOYMENT_LIST=$(eval "kubectl get deployments -n ${NAMESPACE} | awk '/$DEPLOYMENT /'" | awk '{print $1}') # list of multiple deployments when starting with the same name
    if [[ -z "$DEPLOYMENT_LIST" ]]; then
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
      sleep 15
    else
      READY_REPLICAS=$(eval kubectl get deployments "$DEPLOYMENT" -n "$NAMESPACE" -o=jsonpath='{$.status.availableReplicas}')
      if [[ "$READY_REPLICAS" = "$POD_COUNT" ]]; then
        echo "Found deployment ${DEPLOYMENT} in namespace ${NAMESPACE}: ${DEPLOYMENT_LIST}"
        break
      else
          RETRY=$((RETRY+1))
          echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
          sleep 15
      fi
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
    exit 1
  fi
}

function wait_for_daemonset_in_namespace() {
  DAEMONSET=$1; NAMESPACE=$2;
  RETRY=0; RETRY_MAX=40;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    DAEMONSET_LIST=$(eval "kubectl get daemonset -n ${NAMESPACE} | awk '/$DAEMONSET /'" | awk '{print $1}')
    if [[ -z "$DAEMONSET_LIST" ]]; then
      RETRY=$((RETRY+1))
      echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for daemonset ${DAEMONSET} in namespace ${NAMESPACE}"
      sleep 15
    else
      READY_REPLICAS=$(eval kubectl get daemonset "$DAEMONSET" -n "$NAMESPACE" -o=jsonpath='{$.status.desiredNumberScheduled}')
      WANTED_REPLICAS=$(eval kubectl get daemonset "$DAEMONSET" -n "$NAMESPACE" -o=jsonpath='{$.status.numberAvailable}')
      if [[ "$READY_REPLICAS" = "$WANTED_REPLICAS" ]]; then
        echo "Found daemonset ${DAEMONSET} in namespace ${NAMESPACE}: ${DAEMONSET_LIST}"
        break
      else
          RETRY=$((RETRY+1))
          echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for daemonset ${DAEMONSET} in namespace ${NAMESPACE}"
          sleep 15
      fi
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find daemonset ${DAEMONSET} in namespace ${NAMESPACE}"
    exit 1
  fi
}

function verify_deployment_in_namespace() {
  DEPLOYMENT=$1; NAMESPACE=$2;

  DEPLOYMENT_LIST=$(eval "kubectl get deployments -n ${NAMESPACE} | awk '/$DEPLOYMENT /'" | awk '{print $1}') # list of multiple deployments when starting with the same name
  if [[ -z "$DEPLOYMENT_LIST" ]]; then
    print_error "Could not find deployment ${DEPLOYMENT} in namespace ${NAMESPACE}"
    exit 1
  else
    echo "Found deployment ${DEPLOYMENT} in namespace ${NAMESPACE}: ${DEPLOYMENT_LIST}"
  fi
}

function verify_pod_in_namespace() {
  POD=$1; NAMESPACE=$2;

  POD_LIST=$(eval "kubectl get pod -n ${NAMESPACE} | awk '/$POD/'" | awk '{print $1}') # list of multiple deployments when starting with the same name
  if [[ -z "$POD_LIST" ]]; then
    print_error "Could not find pod ${POD} in namespace ${NAMESPACE}"
    exit 1
  else
    echo "Found pod ${POD} in namespace ${NAMESPACE}: ${POD_LIST}"
  fi
}

function verify_namespace_exists() {
  NAMESPACE=$1;

  NAMESPACE_LIST=$(eval "kubectl get namespaces -L istio-injection | grep ${NAMESPACE} | awk '/$NAMESPACE/'" | awk '{print $1}')

  if [[ -z "$NAMESPACE_LIST" ]]; then
    print_error "Could not find namespace ${NAMESPACE}"
    exit 2
  else
    echo "Found namespace ${NAMESPACE}"
  fi
}

function wait_for_problem_open_event() {
  PROJECT=$1; SERVICE=$2; STAGE=$3;
  RETRY=0; RETRY_MAX=15;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    event=$(curl -X GET "${KEPTN_ENDPOINT}/mongodb-datastore/event?project=${PROJECT}&service=${SERVICE}&stage=${STAGE}&type=sh.keptn.event.problem.open" -H  "accept: application/json" -H  "x-token: ${KEPTN_API_TOKEN}" -k 2>/dev/null | jq -r '.events[0]')

    if [[ "${event}" == "null" ]] || [[ "${event}" == "" ]]; then
      RETRY=$((RETRY+1))
      sleep 60
    else
      echo "$event"
      break
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find problem.open event for service ${SERVICE} in project ${PROJECT}"
    exit 1
  fi
}

function wait_for_event_with_field_output() {
  EVENT=$1; FIELD=$2; OUTPUT=$3; PROJECT=$4;

  RETRY=0; RETRY_MAX=50;

  while [[ $RETRY -lt $RETRY_MAX ]]; do
    EVENT_ENTRY=$(keptn get event "${EVENT}" --project "$PROJECT")
    EVENT_DATA=$(echo "${EVENT_ENTRY}" | jq -r "${FIELD}" 2> /dev/null || true)

    if [[ "$OUTPUT" != "$EVENT_DATA" ]]; then
        RETRY=$((RETRY+1))
        echo "Retry: ${RETRY}/${RETRY_MAX} - Wait 15s for event ${EVENT} in project ${PROJECT}"
        sleep 15
    else
        echo "Found event ${EVENT} in project ${PROJECT}"
        break
    fi
  done

  if [[ $RETRY == "$RETRY_MAX" ]]; then
    print_error "Could not find event ${EVENT} in project ${PROJECT}"
    exit 1
  fi
}

function replace_value_in_yaml_file() {
  OLDVAL=$1; NEWVAL=$2; FILE=$3
  sed -i'.bak' -e "s#$OLDVAL#$NEWVAL#g" "$FILE"
}

function verify_sockshop_deployment() {
  PROJECT=$1
  STAGE=$2
  ARTIFACT_IMAGE=$3
  ARTIFACT_IMAGE_TAG=$4
  KEPTN_NAMESPACE=$5
  BLUE_GREEN_DEPLOYMENT=$6

  echo ""
  echo "---------------------------------------------------------------------------------------------------------"
  echo "Checking ${STAGE} deployment (namespace: ${PROJECT}-${STAGE}) for ${ARTIFACT_IMAGE}:${ARTIFACT_IMAGE_TAG}"
  echo "---------------------------------------------------------------------------------------------------------"
  echo ""

  echo "Pre-req: Checking if carts-db is already running..."

  # verify that a carts-db deployment exists
  wait_for_deployment_in_namespace "carts-db" "${PROJECT}-${STAGE}"
  verify_test_step $? "Deployment carts-db not up in ${PROJECT}-${STAGE}, exiting ..."

  # verify that a cards-db pod is up and running
  verify_pod_in_namespace "carts-db" "${PROJECT}-${STAGE}"
  verify_test_step $? "Pod carts-db not found in $${PROJECT}-${STAGE}, exiting ..."

  echo ""
  echo "Checking if carts is up and running..."

  if [[ "${BLUE_GREEN_DEPLOYMENT}" == "true" ]]; then
    # verify that a carts deployment exists (but it does not need to be up, as we need to look for carts-primary)
    wait_and_check_if_deployment_exists "carts" "${PROJECT}-${STAGE}"
    verify_test_step $? "Deployment ${ARTIFACT_IMAGE}:${ARTIFACT_IMAGE_TAG} carts not found in ${PROJECT}-${STAGE}, exiting ..."

    # verify that a blue-green carts deployment is up and running
    wait_for_deployment_with_image_in_namespace "carts-primary" "${PROJECT}-${STAGE}" "${ARTIFACT_IMAGE}:${ARTIFACT_IMAGE_TAG}"
    verify_test_step $? "Deployment carts-primary with image ${ARTIFACT_IMAGE}:${ARTIFACT_IMAGE_TAG} not up in ${PROJECT}-${STAGE}, exiting ..."

    # verify that a blue-green carts pod is up and running
    verify_pod_in_namespace "carts-primary" "${PROJECT}-${STAGE}"
    verify_test_step $? "Pod carts-primary not found, exiting ..."
  else # direct deployment
    # verify that a carts deployment is up and running
    wait_for_deployment_with_image_in_namespace "carts" "${PROJECT}-${STAGE}" "${ARTIFACT_IMAGE}:${ARTIFACT_IMAGE_TAG}"
    verify_test_step $? "Deployment carts with image ${ARTIFACT_IMAGE}:${ARTIFACT_IMAGE_TAG} carts not up in ${PROJECT}-${STAGE}, exiting ..."

    # verify that a carts pod is up and running
    verify_pod_in_namespace "carts" "${PROJECT}-${STAGE}"
    verify_test_step $? "Pod carts not found, exiting ..."
  fi

  echo ""
  echo "Trying to access public URI for carts..."

  # get URL for that deployment
  URL="http://carts.${PROJECT}-${STAGE}.$(kubectl get cm ingress-config -n "${KEPTN_NAMESPACE}" -o=jsonpath='{.data.ingress_hostname_suffix}')"
  # try to access that URL
  wait_for_url "$URL/health"
  verify_test_step $? "Trying to access $URL/health failed"
}
