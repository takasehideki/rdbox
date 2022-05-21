#!/usr/bin/env bash
set -euo pipefail

## References
## https://github.com/keycloak/keycloak-documentation/blob/main/server_development/topics/admin-rest-api.adoc
##
##
## 1. Obtain an access token for user in the realm master with username admin and password
## 2. Invoke the API you need by extracting the value of the access_token property
##
function __getAccessToken() {
  local rep_name=$1
  local BASE_URL=$2
  local username
  local password
  local token_endpoint
  username=$(getPresetSuperAdminName "${rep_name}")
  password=$(__getSuperAdminSecret "${rep_name}")
  token_endpoint=$(curl -fs --cacert "${ROOTCA_FILE}" "$BASE_URL"/auth/realms/master/.well-known/openid-configuration | jq -r '.mtls_endpoint_aliases.token_endpoint')
  ## Execute Admin REST API
  ##
  resp=$(curl -fs --cacert "${ROOTCA_FILE}" -X POST "$token_endpoint" \
    -d "client_id=admin-cli" \
    -d "username=$username" \
    -d "password=$password" \
    -d "grant_type=password"
  )
  echo "$resp" | jq -r ".access_token"
  echo "$resp" | jq -r ".refresh_token"
}

## References
## https://www.getambassador.io/docs/edge-stack/1.14/howtos/auth-kubectl-keycloak/
##
##
## 1. Create a new Realm and Client
## 2. Make sure that http://localhost:8000 and http://localhost:18000 are valid Redirect URIs
## 3. Set access type to confidential and Save (bearerOnly:false, publicClient:false)
## 4. Go to the Credentials tab and note down the secret
## 5. Go to the user tab and create a user with the first name ????
##
function __createEntry() {
  local rep_name=$1
  local BASE_URL=$2
  local access_token=$3
  local cluster_name=$4
  local client_secret
  local password
  local preset_group_name
  local preset_cadmi_name
  local operation_endpoint_url
  local cred_hash_array
  local created_date
  local salt
  local hashed_salted_value
  local hash_iterations
  local fullname_array
  local conf_file
  local http_code
  password=$(__getClusterAdminSecret "${rep_name}")
  client_secret=$(__getClusterK8sSSOSecret "${rep_name}")
  preset_group_name=$(getPresetGroupName)
  preset_cadmi_name=$(getPresetClusterAdminName)
  ## For Userinfo
  IFS="-" read -r -a fullname_array <<< "$preset_cadmi_name"
  first_name=${fullname_array[1]}
  last_name=${fullname_array[0]}
  operation_endpoint_url="$BASE_URL/auth/admin/realms"
  ## For Credentials
  created_date=$(getEpochMillisec)
  cred_hash_array=()
  while IFS='' read -r line; do cred_hash_array+=("$line"); done < <(getHashedPasswordByPbkdf2Sha256 "$password")
  salt=${cred_hash_array[0]}
  hashed_salted_value=${cred_hash_array[1]}
  hash_iterations=${cred_hash_array[2]}
    ## NOTE
    ## !!
    ## This Credentials is a deprecated JSON Schema
    ## >> Using deprecated 'credentials' format in JSON representation for user 'xxxxx'. It will be removed in future versions
    ## !!
    ##
  conf_file="$(getDirNameFor confs)/modules/${rep_name}/entry/$(getConfVersion "${rep_name}" entry)/values.jq.json"
  ## Execute Admin REST API
  ##
  http_code=$(curl -fs -w '%{http_code}' -o /dev/null --cacert "${ROOTCA_FILE}" -X POST "$operation_endpoint_url" \
      -H "Authorization: bearer $access_token" \
      -H "Content-Type: application/json" \
      -d "$(jq -n -r -f "$conf_file" \
          --arg client_secret "$client_secret" \
          --arg cluster_name "$cluster_name" \
          --arg preset_group_name "$preset_group_name" \
          --arg preset_cadmi_name "$preset_cadmi_name" \
          --arg hash_iterations "$hash_iterations" \
          --arg salt "$salt" \
          --arg hashed_salted_value "$hashed_salted_value" \
          --arg created_date "$created_date" \
          --arg first_name "$first_name" \
          --arg last_name "$last_name" \
      )")
  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 299 ];then
    echo "Success create the new entry"
  elif [ "${http_code}" -eq 409 ]; then
    echo "Already exist the same entry"
    return 0
  else
    echo "**ERROR** the HTTP Code is ${http_code}"
    return 1
  fi
    ## New Realm
    ##
  operation_endpoint_url=${operation_endpoint_url}/${cluster_name}
  conf_file="$(getDirNameFor confs)/modules/${rep_name}/entry/$(getConfVersion "${rep_name}" entry)/client_scope.jq.json"
  http_code=$(curl -fs -w '%{http_code}' -o /dev/null --cacert "${ROOTCA_FILE}" -X POST "${operation_endpoint_url}/client-scopes" \
      -H "Authorization: bearer $access_token" \
      -H "Content-Type: application/json" \
      -d "$(jq -n -r -f "$conf_file" \
      )")
  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 299 ];then
    echo "Success create the new entry"
  elif [ "${http_code}" -eq 409 ]; then
    echo "Already exist the same entry"
    return 0
  else
    echo "**ERROR** the HTTP Code is ${http_code}"
    return 1
  fi
    ## New ClientScope(This name is the "groups". pointer the "oidc-group-membership-mapper")
    ##
  conf_file="$(getDirNameFor confs)/modules/${rep_name}/entry/$(getConfVersion "${rep_name}" entry)/client.jq.json"
  http_code=$(curl -fs -w '%{http_code}' -o /dev/null --cacert "${ROOTCA_FILE}" -X POST "$operation_endpoint_url/clients" \
      -H "Authorization: bearer $access_token" \
      -H "Content-Type: application/json" \
      -d "$(jq -n -r -f "$conf_file" \
          --arg client_secret "$client_secret" \
      )")
  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 299 ];then
    echo "Success create the new entry"
  elif [ "${http_code}" -eq 409 ]; then
    echo "Already exist the same entry"
    return 0
  else
    echo "**ERROR** the HTTP Code is ${http_code}"
    return 1
  fi
    ## New Client(ambassador)
    ##
  return $?
}

## References
## https://stackoverflow.com/questions/46689034/logout-user-via-keycloak-rest-api-doesnt-work
##
function __logoutSuperAdmin() {
  local BASE_URL=$1
  local REFLESH_TOKEN=$2
  local revoke_endpoint
  revoke_endpoint=$(curl -fs --cacert "${ROOTCA_FILE}" "$BASE_URL"/auth/realms/master/.well-known/openid-configuration | jq -r '.end_session_endpoint')
  ## Execute Admin REST API
  ##
  curl -fs --cacert "${ROOTCA_FILE}" -X POST "$revoke_endpoint" \
      -d "client_id=admin-cli" \
      -d "refresh_token=$REFLESH_TOKEN"
}

function __getSuperAdminSecret() {
  local rep_name=$1
  kubectl -n "${rep_name}" get secrets "$(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.auth.existingSecret.name')" -o jsonpath='{.data.admin-password}' | base64 --decode
}

function __getClusterAdminSecret() {
  local rep_name=$1
  kubectl -n "${rep_name}" get secrets "$(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.auth.existingSecret.name')" -o jsonpath='{.data.k8s-default-cluster-admin-password}' | base64 --decode
}

function __getClusterK8sSSOSecret() {
  local rep_name=$1
  kubectl -n "${rep_name}" get secrets "$(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.auth.existingSecret.name')" -o jsonpath='{.data.k8s-default-cluster-sso-aes-secret}' | base64 --decode
}

function showVerifierCommand() {
  local rep_name=${1}
  local base_url=${2:-https://$(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.ingress.hostname')}
  echo ""
  echo "## USAGE"
  echo "### The basic keycloak entry has been inserted. Check its status by running:"
  echo "  ### For all realms"
  echo "  ${base_url}/auth/admin"
  echo "    echo Username: \$(helm -n ${rep_name} get values ${rep_name} -o json | jq -r '.auth.adminUser')"
  echo "    echo Password: \$(kubectl -n ${rep_name} get secrets $(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.auth.existingSecret.name') -o jsonpath='{.data.admin-password}' | base64 --decode)"
  echo "  ### For this k8s cluster only (ClusterName: $(getClusterName))"
  echo "  ${base_url}/auth/realms/$(getClusterName)/protocol/openid-connect/auth?client_id=security-admin-console"
  echo "    echo Username: $(getPresetClusterAdminName "${rep_name}")"
  echo "    echo Password: \$(kubectl -n ${rep_name} get secrets $(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.auth.existingSecret.name') -o jsonpath='{.data.k8s-default-cluster-admin-password}' | base64 --decode)"
  return $?
}

function main() {
  local rep_name=$1
  ROOTCA_FILE=${ROOTCA_FILE:-$2}

  ## Build BASE_URL
  ##
  BASE_URL=https://$(helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.ingress.hostname')

  ## Get Token (Acccess and Reflesh)
  ##
  local token_string
  if ! token_string=$(__getAccessToken "${rep_name}" "${BASE_URL}"); then
    echo "Failed to get token"
    exit 1
  fi
  local token_array=()
  while IFS='' read -r line; do token_array+=("$line"); done < <(echo "$token_string")
  local access_token=${token_array[0]}
  REFLESH_TOKEN=${token_array[1]}

  ## Set traps for safe logout
  ##
  trap '__logoutSuperAdmin "${BASE_URL}" "${REFLESH_TOKEN}"' EXIT

  ## Insert entry
  ##
  local cluster_name
  cluster_name=$(getClusterName)
  if ! __createEntry "${rep_name}" "${BASE_URL}" "${access_token}" "${cluster_name}"; then
    echo "Failed to create entry"
    exit 1
  fi

  ## Set Context
  local client_secret
  local __ctx_name
  __ctx_name=$(getKubectlContextName4SSO)
  client_secret=$(__getClusterK8sSSOSecret "${rep_name}")
  echo ""
  echo "### Setting Cluster Context ..."
  if ! kubectl config delete-user "${__ctx_name}" 2>/dev/null; then
    echo "The ClusterContext(user) is Not Found ...ok"
  fi
  kubectl config set-credentials "${__ctx_name}" \
      --exec-api-version=client.authentication.k8s.io/v1beta1 \
      --exec-command=kubectl \
      --exec-arg=oidc-login \
      --exec-arg=get-token \
      --exec-arg=--oidc-issuer-url="${BASE_URL}"/auth/realms/"${cluster_name}" \
      --exec-arg=--oidc-client-id=ambassador \
      --exec-arg=--oidc-client-secret="${client_secret}" \
      --exec-arg=--certificate-authority-data="$(< "${ROOTCA_FILE}" base64 | tr -d '\n' | tr -d '\r')" \
      --exec-arg=--listen-address=0.0.0.0:8000
  ## Notify Verifier-Command
  ##
  showVerifierCommand "${rep_name}" "${BASE_URL}" > "$(getFullpathOfVerifyMsgs "${rep_name}")"

  return $?
}

source "${RDBOX_WORKDIR_OF_SCRIPTS_BASE}/modules/libs/common.bash"
main "$@"
exit $?