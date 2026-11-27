#!/usr/bin/env bash
# Tenta criar uma instância Ampere A1 (Always Free) na Oracle Cloud até haver capacidade.
# Uso: ./criar-a1.sh   (configuração em a1.env, na mesma pasta)
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$DIR/a1.env"

LOG="$DIR/criar-a1.log"
NOME="${NOME:-MINHA_A1}"
DISCO_GB="${DISCO_GB:-50}"            # boot volume; o Always Free soma 200 GB no total
INTERVALO="${INTERVALO:-300}"         # segundos entre ciclos (60 já basta em conta Pay As You Go)
ESPERA_429=900                        # 15 minutos se a API pedir para desacelerar
# Formas tentadas em ordem; ambas dentro do limite Always Free (2 OCPUs / 12 GB).
FORMAS=('{"ocpus":2,"memoryInGBs":12}' '{"ocpus":1,"memoryInGBs":6}')

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

# Evita criar duas instâncias se uma tentativa anterior já tiver funcionado.
ja_existe() {
  # As crases são literais do JMESPath, não expansão do shell.
  # shellcheck disable=SC2016
  oci compute instance list --compartment-id "$COMPARTMENT_ID" \
    --display-name "$NOME" --all \
    --query 'length(data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`])' \
    --raw-output 2>/dev/null
}

tentativa=0
log "Iniciando. Nome: $NOME. Intervalo: ${INTERVALO}s. Log: $LOG"

while true; do
  existentes="$(ja_existe)"
  if [[ "$existentes" =~ ^[1-9] ]]; then
    log "Já existe uma instância '$NOME' ativa. Encerrando."
    exit 0
  fi

  for forma in "${FORMAS[@]}"; do
    tentativa=$((tentativa + 1))
    log "Tentativa $tentativa com $forma"

    saida="$(oci compute instance launch \
      --compartment-id "$COMPARTMENT_ID" \
      --availability-domain "$AVAILABILITY_DOMAIN" \
      --subnet-id "$SUBNET_ID" \
      --image-id "$IMAGE_ID" \
      --shape VM.Standard.A1.Flex \
      --shape-config "$forma" \
      --boot-volume-size-in-gbs "$DISCO_GB" \
      --assign-public-ip true \
      --display-name "$NOME" \
      --ssh-authorized-keys-file "$SSH_PUB_KEY" 2>&1)"
    codigo=$?

    if [[ $codigo -eq 0 ]]; then
      log "SUCESSO com $forma"
      echo "$saida" >> "$LOG"
      log "Veja o IP público no painel em alguns minutos (Compute > Instances > $NOME)."
      exit 0
    fi

    if grep -qiE 'out of host capacity|capacidade insuficiente' <<<"$saida"; then
      log "Sem capacidade para $forma."
      continue
    fi

    if grep -qiE 'TooManyRequests|"status": 429' <<<"$saida"; then
      log "API pediu para desacelerar (429). Aguardando ${ESPERA_429}s."
      sleep "$ESPERA_429"
      continue 2
    fi

    # Qualquer outro erro (permissão, OCID errado, limite de conta) para o script:
    # repetir não resolveria e só encheria o log.
    log "ERRO inesperado (código $codigo). Parando para análise:"
    echo "$saida" | tee -a "$LOG"
    exit 1
  done

  sleep $((INTERVALO + RANDOM % 60))
done
