#!/usr/bin/env bash
set -euo pipefail

function showHeaderCommand() {
  echo ""
  echo "---"
  echo "## Installing filter ..."
  return $?
}

function checkArgs() {
  return $?
}

function main() {
  showHeaderCommand "$@"
  cmdWithIndent "__executor $*"
  verify_string=$(showVerifierCommand)
  echo "${verify_string}" > "$(getFullpathOfVerifyMsgs "ambassador")"
  return $?
}

function showVerifierCommand() {
  echo ""
  echo "## USAGE"
  echo "### **ContainerOS** Execute the following command to run kubectl with single sign-on:"
  echo "  ### **ContainerOS**" 
  echo "  ### When executing any command (kubectl get node in the following case), "
  echo "      the output URL must be accessed by the host OS Web browser"
  echo "    kubectl config use-context $(getContextName4Kubectl)"
  echo "    kubectl get node          # whatever is okay, just choose the one you like"
  echo ""
  echo "### If you want to operate your Kubernetes cluster from HostOS, also run the following command"
  echo "### **HostOS** Execute the following command to run kubectl with single sign-on:"
  echo "  ### **HostOS** First, If you have not installed kubectl"
  echo "      References: https://kubernetes.io/docs/tasks/tools/#kubectl"
  echo "  ### **HostOS** Next, You need to install the krew(Plug-In manager for kubectl)"
  echo "      References: https://krew.sigs.k8s.io/docs/user-guide/quickstart/"
  echo "  ### **HostOS** Next, You need to install the oidc-login (krew's Plug-In)"
  echo "      References: https://github.com/int128/kubelogin"
  echo "  ### **HostOS** Finally, Execute the following command"
  echo "  ### Your default browser will launch and you should perform the login operation"
  echo "    kubectl config use-context $(getContextName4Kubectl)"
  echo "    kubectl get node          # whatever is okay, just choose the one you like"
  return $?
}

function __executor() {
  local __base_fqdn
  __base_fqdn=$(getBaseFQDN)
  local __namespace_for_keycloak
  __namespace_for_keycloak=$(getNamespaceName "keycloak")
  local __hostname_for_keycloak_main
  __hostname_for_keycloak_main=$(getHostName "keycloak" "main")
  local __cluster_name
  __cluster_name=$(getClusterName)
    # rdbox
  local __namespace_for_ambassador
    # ambassador
  local __hostname_for_ambassador_k8ssso
    # ambassador-k8ssso
  local __jwks_uri=http://${__hostname_for_keycloak_main}.${__namespace_for_keycloak}/auth/realms/${__cluster_name}/protocol/openid-connect/certs
    # https://keycloak.rdbox.172-16-0-110.nip.io/auth/realms/rdbox/protocol/openid-connect/certs
  __namespace_for_ambassador=$(getNamespaceName "ambassador")
  __hostname_for_ambassador_k8ssso=$(getHostName "ambassador" "k8ssso")
  ## 1. Install Filter
  ##
  echo ""
  echo "### Applying the filter for Impersonate-Group/User ..."
  applyManifestByDI "${__namespace_for_ambassador}" \
                    "${__hostname_for_ambassador_k8ssso}" \
                    "${__RELEASE_ID}" \
                    180s \
                    ambassador.dynamics.common.baseFqdn="${__base_fqdn}" \
                    ambassador.dynamics.k8ssso.hostname="${__hostname_for_ambassador_k8ssso}" \
                    ambassador.dynamics.k8ssso.filter.jwksUri="${__jwks_uri}"
  ## 2. Set Context
  ##
  local __ctx_name
  __ctx_name=$(getContextName4Kubectl)
  echo ""
  echo "### Setting Cluster Context ..."
  if ! kubectl config delete-context "${__ctx_name}" > /dev/null 2>&1; then
    echo "The ClusterContext(context) is Not Found ...ok"
  fi
  kubectl config set-context "${__ctx_name}" \
      --cluster="${__ctx_name}" \
      --user="${__ctx_name}"
  return $?
}

source "${RDBOX_WORKDIR_OF_SCRIPTS_BASE}/modules/libs/common.bash"
main "$@"
exit $?