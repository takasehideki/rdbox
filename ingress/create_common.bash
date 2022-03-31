#!/bin/bash

## FIXED VALUE
##
CLUSTER_INFO_NAMENAME=cluster-info
CLUSTER_INFO_NAMESPACE=cluster-common
##
##

cleanupShowLoading() {
    tput cnorm
}

showLoading() {
  local mypid=$!
  local loadingText=$1
  tput civis
  trap cleanupShowLoading EXIT
  echo -ne "\r"
  sleep 1
  while kill -0 $mypid 2>/dev/null; do
    echo -ne "\r\033[K"
    echo -ne "    $loadingText\r"
    echo -ne " -  $loadingText\r"
    sleep 0.5
    echo -ne " \\  $loadingText\r"
    sleep 0.5
    echo -ne " |  $loadingText\r"
    sleep 0.5
    echo -ne " /  $loadingText\r"
    sleep 0.5
  done
  tput cnorm
  set +euo > /dev/null 2>&1
  wait $mypid
  local exit_status=$?
  if [ ${exit_status} = 0 ]; then
    echo -e "\033[32mok!\033[m $loadingText"
  else
    echo -e "\033[31mng!\033[m $loadingText"
  fi
  set -euo > /dev/null 2>&1
  return "$exit_status"
}

cmdWithLoding() {
  local commands="$1"
  local message="$2"
  eval "${commands} & showLoading '${message} '"
}

indent() { sed 's/^/    /'; }

cmdWithIndent() {
  local commands="$1"
  esc=$(printf '\033')
  eval "{ ${commands} 3>&1 1>&2 2>&3 | sed 's/^/${esc}[31m[STDOUT]&${esc}[0m -> /' ; } 2>&1 | indent"
}

drawMaxColsSeparator() {
  local char=${1:-#}
  local color=${2:-32}
  local raw_separator
  raw_separator="$(seq -s "${char}" 0 $(($(tput cols)-3)) | tr -d '0-9')"
  printf "\033[${color}m$%s\033[${color}m\n" "${raw_separator}"
}

getNetworkInfo() {
  NAME_DEFULT_NIC=${NAME_DEFULT_NIC:-$(netstat -rn | grep default | grep -v ":" | awk '{print $4}')}
  NAME_DEFULT_NIC=$(printf %q "$NAME_DEFULT_NIC")
    # ExtrapolationValue
  export NAME_DEFULT_NIC
  # shellcheck disable=SC2015
  IP_DEFAULT_NIC=$( (command -v ip &> /dev/null && ip addr show "$NAME_DEFULT_NIC" || ifconfig "$NAME_DEFULT_NIC") | \
                    sed -nEe 's/^[[:space:]]+inet[^[:alnum:]]+([0-9.]+).*$/\1/p')
  export IP_DEFAULT_NIC
  HOSTNAME_FOR_WCDNS_BASED_ON_IP=${IP_DEFAULT_NIC//\./-}
  export HOSTNAME_FOR_WCDNS_BASED_ON_IP
}

updateHelm() {
  cmdWithLoding \
    "helm repo update 1> /dev/null" \
    "Updateing Helm"
}

getContextName() {
  local prefix=${1:-sso}
  local context_name
  context_name=${prefix}-$(getClusterName)
  echo -e "$context_name"
}

getClusterName() {
  kubectl -n ${CLUSTER_INFO_NAMESPACE} get configmaps ${CLUSTER_INFO_NAMENAME} -o json| jq -r ".data.name"
}

getBaseFQDN() {
  kubectl -n ${CLUSTER_INFO_NAMESPACE} get configmaps ${CLUSTER_INFO_NAMENAME} -o json| jq -r ".data.base_fqdn"
}

getIPv4 () {
  kubectl -n ${CLUSTER_INFO_NAMESPACE} get configmaps ${CLUSTER_INFO_NAMENAME} -o json| jq -r '.data["nic.ipv4"]'
}

getPresetSuperAdminName() {
  rep_name=$1
  helm -n "${rep_name}" get values "${rep_name}" -o json | jq -r '.auth.adminUser'
}

getPresetClusterAdminName() {
  getPresetGroupName
}

getPresetGroupName() {
  # !! Must be a hyphen-delimited string !!
  # e.g. *cluster-admim*
  echo -n "cluster-admin"
}

hashPasswordByPbkdf2Sha256() {
  local __password=$1
  local __hash_iterations=27500
  local __salt
  local __hashed_salted_value
  __salt=$(python3 -c 'import crypt; print(crypt.mksalt(crypt.METHOD_SHA256),end="")')
  __salt=${__salt//[\r\n]\+/ }
  # __salt=$(echo -e "import base64; print(base64.b64encode(b\"${__salt}\").decode(encoding=\"ascii\"),end=\"\")" | python3)
  # __salt=${__salt//[\r\n]\+/ }
  #__hashed_salted_value=$(python3 -c "import hashlib, crypt, base64; print(base64.b64encode(hashlib.pbkdf2_hmac(str('sha512'), byte($__password), byte($__salt), int($__hash_iterations))).decode(encoding='utf-8'))")
  __hashed_salted_value=$(echo -e "import hashlib,crypt,base64; print(base64.b64encode(hashlib.pbkdf2_hmac(\"sha256\", b\"$__password\", b\"$__salt\", int($__hash_iterations), 512//8)).decode(\"ascii\"))" | python3)
  __hashed_salted_value=${__hashed_salted_value//[\r\n]\+/ }
  __salt=$(echo -e "import base64; print(base64.b64encode(b\"${__salt}\").decode(encoding=\"ascii\"),end=\"\")" | python3)
  __salt=${__salt//[\r\n]\+/ }
  echo "$__salt"
  echo "$__hashed_salted_value"
  echo "$__hash_iterations"
}

getEpochMillisec() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}