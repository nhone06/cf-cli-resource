
function cf_login() {
  local api_endpoint=${1:?api_endpoint null or not set}
  local cf_user=${2:?cf_user null or not set}
  local cf_pass=${3:?cf_pass null or not set}
  local skip_ssl_validation=${4:-false}

  local args=("$api_endpoint")
  [ "$skip_ssl_validation" = "true" ] && args+=(--skip-ssl-validation)

  cf api "${args[@]}"

  cf auth "$cf_user" "$cf_pass"
}

function cf_target() {
  local org=${1:?org null or not set}
  local space=${2:-}

  local args=(-o "$org")
  [ -n "$space" ] && args+=(-s "$space")

  cf target "${args[@]}"
}

function cf_get_org_guid() {
  local org=${1:?org null or not set}
  # swallow "FAILED" stdout if org not found
  local org_guid=
  if org_guid=$(CF_TRACE=false cf org "$org" --guid 2>/dev/null); then
    echo "$org_guid"
  fi
}

function cf_org_exists() {
  local org=${1:?org null or not set}
  [ -n "$(cf_get_org_guid "$org")" ]
}

function cf_create_org() {
  local org=${1:?org null or not set}
  cf create-org "$org"
}

function cf_delete_org() {
  local org=${1:?org null or not set}
  cf delete-org "$org" -f
}

function cf_get_space_guid() {
  local org=${1:?org null or not set}
  local space=${2:?space null or not set}

  local org_guid="$(cf_get_org_guid "$org")"
  if [ -n "$org_guid" ]; then
    CF_TRACE=false cf curl "/v2/spaces" -X GET -H "Content-Type: application/x-www-form-urlencoded" -d "q=name:$space;organization_guid:$org_guid" | jq -r '.resources[].metadata.guid'
  fi
}

function cf_space_exists() {
  local org=${1:?org null or not set}
  local space=${2:?space null or not set}
  [ -n "$(cf_get_space_guid "$org" "$space")" ]
}

function cf_create_space() {
  local org=${1:?org null or not set}
  local space=${2:?space null or not set}
  cf create-space "$space" -o "$org"
}

function cf_delete_space() {
  local org=${1:?org null or not set}
  local space=${2:?space null or not set}
  cf delete-space "$space" -o "$org" -f
}

function cf_user_exists() {
  local username=${1:?username null or not set}

  local next_url='/v2/users?order-direction=asc&page=1'
  while [ "$next_url" != "null" ]; do

    local output=$(CF_TRACE=false cf curl "$next_url")

    if (echo $output | jq -e --arg username "$username" '.resources[] | select(.entity.username == $username) | true' >/dev/null); then
      return 0
    fi

    next_url=$(echo "$output" | jq -r '.next_url')
  done
  return 1
}

function cf_create_user_with_password() {
  local username=${1:?username null or not set}
  local password=${2:?password null or not set}
  cf create-user "$username" "$password"
}

function cf_create_user_with_origin() {
  local username=${1:?username null or not set}
  local origin=${2:?origin null or not set}
  cf create-user "$username" --origin "$origin"
}

function cf_create_users_from_file() {
  local file=${1:?file null or not set}

  if [ ! -f "$file" ]; then
    printf '\e[91m[ERROR]\e[0m file not found: %s\n' "$file"
    exit 1
  fi

  oldifs=$IFS
  IFS=,

  # First line is the header row, so skip it and start processing at line 2
  linenum=1
  sed 1d "$file" | while read -r Username Password Org Space OrgManager BillingManager OrgAuditor SpaceManager SpaceDeveloper SpaceAuditor
  do
    (( linenum++ ))

    if [ -z "$Username" ]; then
      printf '\e[91m[ERROR]\e[0m no Username specified, unable to process line number: %s\n' "$linenum"
      continue
    fi

    if [ -n "$Password" ]; then
      cf create-user "$Username" "$Password"
    fi


    if [ -n "$Org" ]; then
      [ -n "$OrgManager" ]     && cf set-org-role "$Username" "$Org" OrgManager
      [ -n "$BillingManager" ] && cf set-org-role "$Username" "$Org" BillingManager
      [ -n "$OrgAuditor" ]     && cf set-org-role "$Username" "$Org" OrgAuditor

      if [ -n "$Space" ]; then
        [ -n "$SpaceManager" ]   && cf set-space-role "$Username" "$Org" "$Space" SpaceManager
        [ -n "$SpaceDeveloper" ] && cf set-space-role "$Username" "$Org" "$Space" SpaceDeveloper
        [ -n "$SpaceAuditor" ]   && cf set-space-role "$Username" "$Org" "$Space" SpaceAuditor
      fi
    fi
  done

  IFS=$oldifs
}

function cf_delete_user() {
  local username=${1:?username null or not set}
  cf delete-user -f "$username"
}

cf_has_private_domain() {
  local org=${1:?org null or not set}
  local domain=${2:?domain null or not set}
  local org_guid=$(cf_get_org_guid "$org")
  CF_TRACE=false cf curl "/v2/organizations/$org_guid/private_domains?q=name:$domain" | jq -e '.total_results == 1' >/dev/null
}

function cf_create_domain() {
  local org=${1:?org null or not set}
  local domain=${2:?domain null or not set}
  cf create-domain "$org" "$domain"
}

function cf_delete_domain() {
  local domain=${1:?domain null or not set}
  cf delete-domain -f "$domain"
}

function cf_map_route() {
  local app_name=${1:?app_name null or not set}
  local domain=${2:?domain null or not set}
  local hostname=${3:-}
  local path=${4:-}

  local args=("$app_name" "$domain")
  [ -n "$hostname" ] && args+=(--hostname "$hostname")
  [ -n "$path" ] && args+=(--path "$path")

  cf map-route "${args[@]}"
}

function cf_unmap_route() {
  local app_name=${1:?app_name null or not set}
  local domain=${2:?domain null or not set}
  local hostname=${3:-}
  local path=${4:-}

  local args=("$app_name" "$domain")
  [ -n "$hostname" ] && args+=(--hostname "$hostname")
  [ -n "$path" ] && args+=(--path "$path")

  cf unmap-route "${args[@]}"
}

# returns the app guid, otherwise null if not found
function cf_get_app_guid() {
  local app_name=${1:?app_name null or not set}
  CF_TRACE=false cf app "$app_name" --guid
}

# returns the service instance guid, otherwise null if not found
function cf_get_service_instance_guid() {
  local service_instance=${1:?service_instance null or not set}
  # swallow "FAILED" stdout if service not found
  local service_instance_guid=
  if service_instance_guid=$(CF_TRACE=false cf service "$service_instance" --guid 2>/dev/null); then
    echo "$service_instance_guid"
  fi
}

# returns true if service exists, otherwise false
function cf_service_exists() {
  local service_instance=${1:?service_instance null or not set}
  local service_instance_guid=$(cf_get_service_instance_guid "$service_instance")
  [ -n "$service_instance_guid" ]
}

function cf_create_user_provided_service_credentials() {
  local service_instance=${1:?service_instance null or not set}
  local credentials=${2:?credentials json null or not set}

  local json=$credentials
  if [ -f "$credentials" ]; then
    json=$(cat $credentials)
  fi

  # validate the json
  if echo "$json" | jq . 1>/dev/null 2>&1; then
    cf create-user-provided-service "$service_instance" -p "$json"
  else
    printf '\e[91m[ERROR]\e[0m invalid credentials payload (must be valid json string or json file)\n'
    exit 1
  fi
}

function cf_create_user_provided_service_syslog() {
  local service_instance=${1:?service_instance null or not set}
  local syslog_drain_url=${2:?syslog_drain_url null or not set}
  cf create-user-provided-service "$service_instance" -l "$syslog_drain_url"
}

function cf_create_user_provided_service_route() {
  local service_instance=${1:?service_instance null or not set}
  local route_service_url=${2:?route_service_url null or not set}
  cf create-user-provided-service "$service_instance" -r "$route_service_url"
}

function cf_create_service() {
  local service=${1:?service null or not set}
  local plan=${2:?plan null or not set}
  local service_instance=${3:?service_instance null or not set}
  local configuration=${4:-}
  local tags=${5:-}

  local args=("$service" "$plan" "$service_instance")
  [ -n "$configuration" ] && args+=(-c "$configuration")
  [ -n "$tags" ] && args+=(-t "$tags")

  cf create-service "${args[@]}"
}

function cf_delete_service() {
  local service_instance=${1:?service_instance null or not set}
  cf delete-service "$service_instance" -f
}

function cf_wait_for_service_instance() {
  local service_instance=${1:?service_instance null or not set}
  local timeout=${2:-600}

  local guid=$(cf_get_service_instance_guid "$service_instance")
  if [ -z "$guid" ]; then
    printf '\e[91m[ERROR]\e[0m Service instance does not exist: %s\n' "$service_instance"
    exit 1
  fi

  local start=$(date +%s)

  printf '\e[92m[INFO]\e[0m Waiting for service: %s\n' "$service_instance"
  while true; do
    # Get the service instance info in JSON from CC and parse out the async 'state'
    local state=$(CF_TRACE=false cf curl "/v2/service_instances/$guid" | jq -r .entity.last_operation.state)

    if [ "$state" = "succeeded" ]; then
      printf '\e[92m[INFO]\e[0m Service is ready: %s\n' "$service_instance"
      return
    elif [ "$state" = "failed" ]; then
      printf '\e[91m[ERROR]\e[0m Failed to provision service: %s, error: %s\n' \
        "$service_instance" \
        $(CF_TRACE=false cf curl "/v2/service_instances/$guid" | jq -r .entity.last_operation.description)
      exit 1
    fi

    local now=$(date +%s)
    local time=$(($now - $start))
    if [[ "$time" -ge "$timeout" ]]; then
      printf '\e[91m[ERROR]\e[0m Timed out waiting for service instance to provision: %s\n' "$service_instance"
      exit 1
    fi
    sleep 5
  done
}

function cf_wait_for_delete_service_instance() {
  local service_instance=${1:?service_instance null or not set}
  local timeout=${2:-600}

  local start=$(date +%s)

  printf '\e[92m[INFO]\e[0m Waiting for service deletion: %s\n' "$service_instance"
  while true; do
    if ! (cf_service_exists "$service_instance"); then
      printf '\e[92m[INFO]\e[0m Service deleted: %s\n' "$service_instance"
      return
    fi

    local now=$(date +%s)
    local time=$(($now - $start))
    if [[ "$time" -ge "$timeout" ]]; then
      printf '\e[91m[ERROR]\e[0m Timed out waiting for service instance to delete: %s\n' "$service_instance"
      exit 1
    fi
    sleep 5
  done
}

function cf_create_service_broker() {
  local service_broker=${1:?service_broker null or not set}
  local username=${2:?username null or not set}
  local password=${3:?password null or not set}
  local url=${4:?broker_url null or not set}
  local is_space_scoped=${5:-}

  local space_scoped=
  if [ "$is_space_scoped" = "true" ]; then
    space_scoped="--space-scoped"
  fi

  if cf_service_broker_exists "$service_broker"; then
    cf update-service-broker "$service_broker" "$username" "$password" "$url"
  else
    cf create-service-broker "$service_broker" "$username" "$password" "$url" $space_scoped
  fi
}

function cf_enable_service_access() {
  local service_broker=${1:?service_broker null or not set}
  local plan=${2:-}
  local access_org=${3:-}

  local args=("$service_broker")
  [ -n "$plan" ] && args+=(-p "$plan")
  [ -n "$access_org" ] && args+=(-o "$access_org")

  cf enable-service-access "${args[@]}"
}

function cf_disable_service_access() {
  local service_broker=${1:?service_broker null or not set}
  local plan=${2:-}
  local access_org=${3:-}

  local args=("$service_broker")
  [ -n "$plan" ] && args+=(-p "$plan")
  [ -n "$access_org" ] && args+=(-o "$access_org")

  cf disable-service-access "${args[@]}"
}

function cf_delete_service_broker() {
  local service_broker=${1:?service_broker null or not set}
  cf delete-service-broker "$service_broker" -f
}

function cf_bind_service() {
  local app_name=${1:?app_name null or not set}
  local service_instance=${2:?service_instance null or not set}
  local configuration=${3:-}

  local args=("$app_name" "$service_instance")
  [ -n "$configuration" ] && args+=(-c "$configuration")

  cf bind-service "${args[@]}"
}

function cf_unbind_service() {
  local app_name=${1:?app_name null or not set}
  local service_instance=${2:?service_instance null or not set}
  cf unbind-service "$app_name" "$service_instance"
}

function cf_is_app_bound_to_service() {
  local app_name=${1:?app_name null or not set}
  local service_instance=${2:?service_instance null or not set}
  local app_guid=$(cf_get_app_guid "$app_name")
  local si_guid=$(CF_TRACE=false cf service "$service_instance" --guid)
  CF_TRACE=false cf curl "/v2/apps/$app_guid/service_bindings" -X GET -H "Content-Type: application/x-www-form-urlencoded" -d "q=service_instance_guid:$si_guid" | jq -e '.total_results == 1' >/dev/null
}

function cf_push() {
  local args=${1:?args null or not set}
  cf push $args
}

function cf_zero_downtime_push() {
  local args=${1:?args null or not set}
  local current_app_name=${2:-}
  if [ -n "$current_app_name" ]; then
    # autopilot (tested v0.0.2 - v0.0.6) doesn't like CF_TRACE=true
    CF_TRACE=false cf zero-downtime-push "$current_app_name" $args
  else
    cf push $args
  fi
}

function cf_start() {
  local app_name=${1:?app_name null or not set}
  local staging_timeout=${2:-0}
  local startup_timeout=${3:-0}

  if [ "$staging_timeout" -gt "0" ]; then
    export CF_STAGING_TIMEOUT=$staging_timeout
  fi
  if [ "$startup_timeout" -gt "0" ]; then
    export CF_STARTUP_TIMEOUT=$startup_timeout
  fi

  cf start "$app_name"

  unset CF_STAGING_TIMEOUT
  unset CF_STARTUP_TIMEOUT
}

function cf_stop() {
  local app_name=${1:?app_name null or not set}

  cf stop "$app_name"
}

function cf_restart() {
  local app_name=${1:?app_name null or not set}
  local staging_timeout=${2:-0}
  local startup_timeout=${3:-0}

  if [ "$staging_timeout" -gt "0" ]; then
    export CF_STAGING_TIMEOUT=$staging_timeout
  fi
  if [ "$startup_timeout" -gt "0" ]; then
    export CF_STARTUP_TIMEOUT=$startup_timeout
  fi

  cf restart "$app_name"

  unset CF_STAGING_TIMEOUT
  unset CF_STARTUP_TIMEOUT
}

function cf_restage() {
  local app_name=${1:?app_name null or not set}
  local staging_timeout=${2:-0}
  local startup_timeout=${3:-0}

  if [ "$staging_timeout" -gt "0" ]; then
    export CF_STAGING_TIMEOUT=$staging_timeout
  fi
  if [ "$startup_timeout" -gt "0" ]; then
    export CF_STARTUP_TIMEOUT=$startup_timeout
  fi

  cf restage "$app_name"

  unset CF_STAGING_TIMEOUT
  unset CF_STARTUP_TIMEOUT
}

function cf_delete() {
  local app_name=${1:?app_name null or not set}
  local delete_mapped_routes=${2:-}

  if [ -n "$delete_mapped_routes" ]; then
    cf delete "$app_name" -f -r
  else
    cf delete "$app_name" -f
  fi
}

function cf_run_task() {
  local app_name=${1:?app_name null or not set}
  local task_command=${2:?task_command null or not set}
  local task_name=${3:-}
  local memory=${4:-}
  local disk_quota=${5:-}

  local args=("$app_name" "$task_command")
  [ -n "$task_name" ] && args+=(--name "$task_name")
  [ -n "$memory" ] && args+=(-m "$memory")
  [ -n "$disk_quota" ] && args+=(-k "$disk_quota")

  cf run-task "${args[@]}"
}

# very loose match on some "task name" (or command...) in the cf tasks output
function cf_was_task_run() {
  local app_name=${1:?app_name null or not set}
  local task_name=${2:?task_name null or not set}
  CF_TRACE=false cf tasks "$app_name" | grep "$task_name" >/dev/null
}

function cf_is_app_started() {
  local app_name=${1:?app_name null or not set}
  local guid=$(cf_get_app_guid "$app_name")
  CF_TRACE=false cf curl "/v2/apps/$guid" | jq -e '.entity.state == "STARTED"' >/dev/null
}

function cf_is_app_stopped() {
  local app_name=${1:?app_name null or not set}
  local guid=$(cf_get_app_guid "$app_name")
  CF_TRACE=false cf curl "/v2/apps/$guid" | jq -e '.entity.state == "STOPPED"' >/dev/null
}

function cf_app_exists() {
  local app_name=${1:?app_name null or not set}
  cf_get_app_guid "$app_name" >/dev/null 2>&1
}

function cf_get_app_instances() {
  local app_name=${1:?app_name null or not set}
  local guid=$(cf_get_app_guid "$app_name")
  cf curl "/v2/apps/$guid" | jq -r '.entity.instances'
}

function cf_get_app_memory() {
  local app_name=${1:?app_name null or not set}
  local guid=$(cf_get_app_guid "$app_name")
  cf curl "/v2/apps/$guid" | jq -r '.entity.memory'
}

function cf_get_app_disk_quota() {
  local app_name=${1:?app_name null or not set}
  local guid=$(cf_get_app_guid "$app_name")
  cf curl "/v2/apps/$guid" | jq -r '.entity.disk_quota'
}

function cf_scale() {
  local app_name=${1:?app_name null or not set}
  local instances=${2:-}
  local memory=${3:-}
  local disk_quota=${4:-}

  local args=(-f "$app_name")
  [ -n "$instances" ] && args+=(-i "$instances")
  [ -n "$memory" ] && args+=(-m "$memory")
  [ -n "$disk_quota" ] && args+=(-k "$disk_quota")

  cf scale "${args[@]}"
}

function cf_service_broker_exists() {
  local service_broker=${1:?service_broker null or not set}
  CF_TRACE=false cf curl /v2/service_brokers | jq -e --arg name "$service_broker" '.resources[] | select(.entity.name == $name) | true' >/dev/null
}

function cf_is_marketplace_service_available() {
  local service_name=${1:?service_name null or not set}
  local plan=${2:?plan null or not set}
  CF_TRACE=false cf marketplace | grep "$service_name" | grep "$plan" >/dev/null
}

function cf_enable_feature_flag() {
  local feature_name=${1:?feature_name null or not set}
  CF_TRACE=false cf enable-feature-flag "$feature_name"
}

function cf_disable_feature_flag() {
  local feature_name=${1:?feature_name null or not set}
  CF_TRACE=false cf disable-feature-flag "$feature_name"
}

function cf_is_feature_flag_enabled() {
  local feature_flag=${1:?feature_flag null or not set}
  CF_TRACE=false cf feature-flags | grep service_instance_sharing | grep -q enabled
}

function cf_is_feature_flag_disabled() {
  local feature_flag=${1:?feature_flag null or not set}
  CF_TRACE=false cf feature-flags | grep service_instance_sharing | grep -q disabled
}
