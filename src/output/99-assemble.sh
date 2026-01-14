# shellcheck shell=bash
# shellcheck disable=SC2154  # Variables from domain components
# ============================================================================
# Output: Assemble and render domains
# Requires: domain_resources, domain_rhythm, domain_focus, domain_infra,
#           domain_session (from domain components)
#           SHOW_*, DOMAIN_ORDER (from core/constants)
# ============================================================================

# Build array of enabled domains in configured order
domains=()
IFS=',' read -ra order <<<"$DOMAIN_ORDER"
for d in "${order[@]}"; do
    case "$d" in
    resources) [ "$SHOW_RESOURCES" = "1" ] && [ -n "$domain_resources" ] && domains+=("$domain_resources") ;;
    rhythm) [ "$SHOW_RHYTHM" = "1" ] && [ -n "$domain_rhythm" ] && domains+=("$domain_rhythm") ;;
    focus) [ "$SHOW_FOCUS" = "1" ] && [ -n "$domain_focus" ] && domains+=("$domain_focus") ;;
    infra) [ "$SHOW_INFRA" = "1" ] && [ -n "$domain_infra" ] && domains+=("$domain_infra") ;;
    session) [ "$SHOW_SESSION" = "1" ] && [ -n "$domain_session" ] && domains+=("$domain_session") ;;
    esac
done

# Print domains with tree connectors
count=${#domains[@]}
for i in "${!domains[@]}"; do
    if [ $((i + 1)) -eq "$count" ]; then
        printf "\033[2m└─\033[0m %b\n" "${domains[$i]}"
    else
        printf "\033[2m├─\033[0m %b\n" "${domains[$i]}"
    fi
done
