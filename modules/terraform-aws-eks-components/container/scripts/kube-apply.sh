#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

log_error() {
  echo "[$(date -Iseconds)] ERROR: $*" >&2
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log_error "required environment variable ${name} is not set"
    exit 1
  fi
}

WORKDIR=""
RESULT_WRITTEN=0
CURRENT_STEP=""
STEPS_FILE=""
SNAPSHOT_URI=""

write_result() {
  local status="$1"
  local failed="${2:-}"
  local steps_json="[]"

  if [[ -n "${STEPS_FILE}" && -f "${STEPS_FILE}" ]]; then
    steps_json="$(cat "${STEPS_FILE}")"
  fi

  jq -n \
    --arg status "${status}" \
    --arg cluster "${CLUSTER_NAME:-}" \
    --arg failed "${failed}" \
    --argjson steps "${steps_json}" \
    '{
      status: $status,
      cluster_name: $cluster,
      failed_step: (if $failed == "" then null else $failed end),
      steps: $steps
    }' > "${WORKDIR}/result.json"

  aws s3 cp "${WORKDIR}/result.json" "${PACK_URI}/result.json" >/dev/null
  if [[ -n "${SNAPSHOT_URI:-}" ]]; then
    aws s3 cp "${WORKDIR}/result.json" "${SNAPSHOT_URI}/result.json" >/dev/null
  fi
  RESULT_WRITTEN=1
}

append_step_result() {
  local id="$1"
  local kind="$2"
  local status="$3"
  local tmp
  tmp="$(mktemp)"
  jq --arg id "${id}" --arg kind "${kind}" --arg status "${status}" \
    '. + [{id: $id, kind: $kind, status: $status}]' \
    "${STEPS_FILE}" > "${tmp}"
  mv "${tmp}" "${STEPS_FILE}"
}

on_exit() {
  local code=$?
  if [[ "${RESULT_WRITTEN}" -eq 0 ]]; then
    if [[ "${code}" -eq 0 ]]; then
      write_result "ok" || true
    else
      write_result "error" "${CURRENT_STEP:-unknown}" || true
    fi
  fi
  exit "${code}"
}

trap on_exit EXIT

require_env PACK_URI
require_env CLUSTER_NAME
require_env AWS_REGION

export AWS_DEFAULT_REGION="${AWS_REGION}"

WORKDIR="$(mktemp -d)"
STEPS_FILE="${WORKDIR}/step-results.json"
echo '[]' > "${STEPS_FILE}"

log "downloading pack from ${PACK_URI}"
aws s3 sync "${PACK_URI}" "${WORKDIR}" --exclude "result.json"

if [[ ! -f "${WORKDIR}/run.json" ]]; then
  log_error "pack is missing run.json"
  exit 1
fi

apply_id="$(jq -r '.apply_id // empty' "${WORKDIR}/run.json")"
if [[ -n "${apply_id}" ]]; then
  pack_rest="${PACK_URI#s3://}"
  bucket="${pack_rest%%/*}"
  SNAPSHOT_URI="s3://${bucket}/runs/${apply_id}"
  log "snapshotting pack to ${SNAPSHOT_URI}"
  aws s3 sync "${WORKDIR}" "${SNAPSHOT_URI}" --exclude "result.json" --exclude "kubeconfig"
fi

log "updating kubeconfig for cluster ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --kubeconfig "${WORKDIR}/kubeconfig"
export KUBECONFIG="${WORKDIR}/kubeconfig"

step_count="$(jq '.steps | length' "${WORKDIR}/run.json")"
log "applying ${step_count} step(s)"

idx=0
while [[ "${idx}" -lt "${step_count}" ]]; do
  step="$(jq -c --argjson i "${idx}" '.steps[$i]' "${WORKDIR}/run.json")"
  step_id="$(jq -r '.id // empty' <<<"${step}")"
  kind="$(jq -r '.kind // empty' <<<"${step}")"
  source="$(jq -r '.source // empty' <<<"${step}")"
  url="$(jq -r '.url // empty' <<<"${step}")"
  path="$(jq -r '.path // empty' <<<"${step}")"
  repository="$(jq -r '.repository // empty' <<<"${step}")"
  chart="$(jq -r '.chart // empty' <<<"${step}")"
  version="$(jq -r '.version // empty' <<<"${step}")"
  release="$(jq -r '.release // empty' <<<"${step}")"
  namespace="$(jq -r '.namespace // empty' <<<"${step}")"
  create_namespace="$(jq -r '.create_namespace // false' <<<"${step}")"
  values_file="$(jq -r '.values_file // empty' <<<"${step}")"
  flags=()
  while IFS= read -r flag; do
    flags+=("${flag}")
  done < <(jq -r '.flags // [] | .[]' <<<"${step}")

  CURRENT_STEP="${step_id}"
  log "step ${step_id} kind=${kind} source=${source}"

  local_path=""
  if [[ -n "${path}" ]]; then
    local_path="${WORKDIR}/${path}"
  fi
  local_values=""
  if [[ -n "${values_file}" ]]; then
    local_values="${WORKDIR}/${values_file}"
  fi

  case "${kind}" in
    kubectl)
      kubectl_args=(apply)
      if [[ ${#flags[@]} -gt 0 ]]; then
        kubectl_args+=("${flags[@]}")
      fi
      if [[ "${source}" == "url" ]]; then
        kubectl_args+=(-f "${url}")
      else
        kubectl_args+=(-f "${local_path}")
      fi
      kubectl "${kubectl_args[@]}"
      ;;
    kustomize)
      kustomize_args=(apply)
      if [[ ${#flags[@]} -gt 0 ]]; then
        kustomize_args+=("${flags[@]}")
      fi
      if [[ "${source}" == "url" ]]; then
        kustomize_args+=(-k "${url}")
      else
        kustomize_args+=(-k "${local_path}")
      fi
      kubectl "${kustomize_args[@]}"
      ;;
    helm)
      helm_args=(upgrade --install)
      if [[ ${#flags[@]} -gt 0 ]]; then
        helm_args+=("${flags[@]}")
      fi
      if [[ -n "${namespace}" ]]; then
        helm_args+=(--namespace "${namespace}")
      fi
      if [[ "${create_namespace}" == "true" ]]; then
        helm_args+=(--create-namespace)
      fi
      if [[ -n "${version}" ]]; then
        helm_args+=(--version "${version}")
      fi
      if [[ -n "${local_values}" ]]; then
        helm_args+=(--values "${local_values}")
      fi

      if [[ "${source}" == "file" ]]; then
        helm "${helm_args[@]}" "${release}" "${local_path}"
      elif [[ "${repository}" == oci://* ]]; then
        helm "${helm_args[@]}" "${release}" "${repository}/${chart}"
      else
        helm "${helm_args[@]}" "${release}" "${chart}" --repo "${repository}"
      fi
      ;;
    *)
      log_error "unsupported kind: ${kind}"
      append_step_result "${step_id}" "${kind}" "error"
      write_result "error" "${step_id}"
      exit 1
      ;;
  esac

  append_step_result "${step_id}" "${kind}" "ok"
  idx=$((idx + 1))
done

CURRENT_STEP=""
write_result "ok"
log "all steps applied"
