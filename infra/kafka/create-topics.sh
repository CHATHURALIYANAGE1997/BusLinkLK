#!/usr/bin/env bash
# Creates or updates every topic in topics.conf. Safe to run any number of times:
#   - missing topic            -> created with its partitions and configs
#   - fewer partitions         -> increased
#   - more partitions          -> warning only (Kafka cannot shrink a topic)
#   - config differs           -> updated
#   - everything matches       -> left alone
#
# Runs in the kafka-init container after the broker is healthy. To run it again by hand:
#   docker compose -f infra/docker-compose.yml run --rm kafka-init
set -euo pipefail

BOOTSTRAP="${BOOTSTRAP_SERVERS:-kafka:29092}"
TOPICS_FILE="${TOPICS_FILE:-/buslink/kafka/topics.conf}"
REPLICATION_FACTOR="${REPLICATION_FACTOR:-1}"
BIN="${KAFKA_BIN:-/opt/kafka/bin}"

log() { echo "kafka-init: $*"; }

# Read the current state once, so a re-run costs three tool calls instead of one per topic.
existing_topics=$("$BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" --list --exclude-internal)
partition_counts=$("$BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" --describe --exclude-internal \
  | awk '$1=="Topic:" { for (i = 1; i <= NF; i++) if ($i == "PartitionCount:") print $2, $(i + 1) }')
# "topic key=value" for every config set on a topic (dynamic configs only)
topic_configs=$("$BIN/kafka-configs.sh" --bootstrap-server "$BOOTSTRAP" --describe --entity-type topics \
  | awk '/^Dynamic configs for topic/ { t = $5; next } t != "" && $1 ~ /=/ { print t, $1 }')

created=0 changed=0 unchanged=0 warnings=0

while read -r name partitions configs _; do
  [[ -z "${name}" || "${name}" == \#* ]] && continue

  if ! grep -qxF "${name}" <<<"${existing_topics}"; then
    config_args=()
    IFS=',' read -ra kvs <<<"${configs}"
    for kv in "${kvs[@]}"; do config_args+=(--config "${kv}"); done
    "$BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
      --topic "${name}" --partitions "${partitions}" --replication-factor "${REPLICATION_FACTOR}" \
      "${config_args[@]}" > /dev/null
    log "created   ${name} (${partitions} partitions, ${configs})"
    created=$((created + 1))
    continue
  fi

  topic_changed=false

  current=$(awk -v t="${name}" '$1 == t { print $2 }' <<<"${partition_counts}")
  if (( current < partitions )); then
    "$BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" --alter --topic "${name}" --partitions "${partitions}" > /dev/null
    log "updated   ${name}: partitions ${current} -> ${partitions}"
    topic_changed=true
  elif (( current > partitions )); then
    log "WARNING   ${name} has ${current} partitions, topics.conf says ${partitions}; Kafka cannot reduce partitions"
    warnings=$((warnings + 1))
  fi

  missing=()
  IFS=',' read -ra kvs <<<"${configs}"
  for kv in "${kvs[@]}"; do
    grep -qxF "${name} ${kv}" <<<"${topic_configs}" || missing+=("${kv}")
  done
  if (( ${#missing[@]} > 0 )); then
    joined=$(IFS=','; echo "${missing[*]}")
    "$BIN/kafka-configs.sh" --bootstrap-server "$BOOTSTRAP" --alter --entity-type topics \
      --entity-name "${name}" --add-config "${joined}" > /dev/null
    log "updated   ${name}: ${joined}"
    topic_changed=true
  fi

  if [[ "${topic_changed}" == true ]]; then changed=$((changed + 1)); else unchanged=$((unchanged + 1)); fi
done < "${TOPICS_FILE}"

log "done: ${created} created, ${changed} updated, ${unchanged} unchanged, ${warnings} warnings"
