#!/usr/bin/env zsh
# openstack-lab.zsh — Single entry point for the OpenStack lab
# Usage: ./openstack-lab.zsh <command> [--force]

set -euo pipefail

# Resolve project root
LAB_PROJECT_ROOT="${0:A:h}"
export LAB_PROJECT_ROOT

# Source all modules
source "${LAB_PROJECT_ROOT}/lib/common.zsh"
source "${LAB_PROJECT_ROOT}/lib/logging.zsh"
source "${LAB_PROJECT_ROOT}/lib/config.zsh"
source "${LAB_PROJECT_ROOT}/lib/preflight.zsh"
source "${LAB_PROJECT_ROOT}/lib/libvirt.zsh"
source "${LAB_PROJECT_ROOT}/lib/cloudinit.zsh"
source "${LAB_PROJECT_ROOT}/lib/guest.zsh"
source "${LAB_PROJECT_ROOT}/lib/kolla.zsh"
source "${LAB_PROJECT_ROOT}/lib/verify.zsh"
source "${LAB_PROJECT_ROOT}/lib/cleanup.zsh"
source "${LAB_PROJECT_ROOT}/lib/status.zsh"

# Load and validate config
config_load
config_validate

# --- Usage ---

usage() {
    cat <<EOF
Usage: ./openstack-lab.zsh <command> [options]

Commands:
  help              Show this help message
  preflight         Check host readiness (PASS/WARN/FAIL)
  create-vm         Create KVM VM with cloud-init
  wait              Wait for SSH + cloud-init completion
  configure         Configure guest packages (Docker, etc.)
  install-kolla     Install Kolla-Ansible in venv on guest
  generate-config   Generate globals.yml, multinode, passwords
  bootstrap         Run Kolla bootstrap
  deploy            Run Kolla deployment (includes post-fix)
  post-fix          Fix passwords, networking, restart all containers
  start             Start OpenStack services in correct order
  stop              Gracefully stop OpenStack services
  verify            Full smoke test (image, network, instance)
  status            Show host/VM/Docker/OpenStack state
  logs              Show latest log file
  destroy           Remove all lab resources (interactive)
  rebuild           destroy + full rebuild
  build             Run all stages sequentially
  tofu-init         Initialize OpenTofu
  tofu-plan         Preview OpenTofu changes
  tofu-apply        Apply OpenTofu changes (create resources)
  tofu-destroy      Destroy OpenTofu resources
  tofu-status       Show OpenTofu state

Options:
  --force           Skip state checks and re-run stage

Examples:
  ./openstack-lab.zsh preflight
  ./openstack-lab.zsh build
  ./openstack-lab.zsh destroy
  sudo ./openstack-lab.zsh destroy
EOF
}

# --- Stage Runners ---

stage_preflight() {
    if state_ok "00-preflight" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Preflight already passed (use --force to re-run)"
        return 0
    fi
    log_start "preflight"
    preflight_all
    state_set "00-preflight"
}

stage_create_vm() {
    if state_ok "01-create-vm" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "VM already created (use --force to re-run)"
        return 0
    fi
    log_start "create-vm"
    libvirt_pool_check
    libvirt_base_image
    cloudinit_generate_user_data
    cloudinit_generate_meta_data
    libvirt_create_disk
    libvirt_create_seed
    libvirt_create_vm
    state_set "01-create-vm"
}

stage_wait() {
    if state_ok "02-wait" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "SSH wait already passed (use --force to re-run)"
        return 0
    fi
    log_start "wait"
    local ip
    ip=$(guest_get_ip)
    guest_wait_ssh "${ip}"
    guest_wait_cloud_init "${ip}"
    state_set "02-wait"
}

stage_configure() {
    if state_ok "03-configure" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Guest already configured (use --force to re-run)"
        return 0
    fi
    log_start "configure"
    local ip
    ip=$(guest_get_ip)
    guest_configure "${ip}"
    state_set "03-configure"
}

stage_install_kolla() {
    if state_ok "04-install-kolla" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Kolla already installed (use --force to re-run)"
        return 0
    fi
    log_start "install-kolla"
    local ip
    ip=$(guest_get_ip)
    kolla_install "${ip}"
    state_set "04-install-kolla"
}

stage_generate_config() {
    if state_ok "05-generate-config" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Kolla config already generated (use --force to re-run)"
        return 0
    fi
    log_start "generate-config"
    local ip
    ip=$(guest_get_ip)
    kolla_generate_config "${ip}"
    kolla_prechecks "${ip}"
    state_set "05-generate-config"
}

stage_bootstrap() {
    if state_ok "06-bootstrap" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Bootstrap already done (use --force to re-run)"
        return 0
    fi
    log_start "bootstrap"
    local ip
    ip=$(guest_get_ip)
    kolla_bootstrap "${ip}"
    state_set "06-bootstrap"
}

stage_deploy() {
    if state_ok "07-deploy" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Already deployed (use --force to re-run)"
        return 0
    fi
    log_start "deploy"
    local ip
    ip=$(guest_get_ip)
    kolla_deploy "${ip}"
    kolla_create_admin_creds "${ip}"
    kolla_post_deploy_fix "${ip}"
    state_set "07-deploy"
}

stage_verify() {
    if state_ok "08-verify" && [[ "${FORCE:-}" != "true" ]]; then
        log_info "Already verified (use --force to re-run)"
        return 0
    fi
    log_start "verify"
    local ip
    ip=$(guest_get_ip)
    verify_all
    state_set "08-verify"
}

# --- Main ---

main() {
    local command="${1:-help}"
    FORCE="false"

    # Parse options
    shift || true
    for arg in "$@"; do
        case "${arg}" in
            --force) FORCE="true" ;;
            *) log_fatal "Unknown option: ${arg}" ;;
        esac
    done

    case "${command}" in
        help|-h|--help)
            usage
            ;;
        preflight)
            stage_preflight
            ;;
        create-vm)
            stage_create_vm
            ;;
        wait)
            stage_wait
            ;;
        configure)
            stage_configure
            ;;
        install-kolla)
            stage_install_kolla
            ;;
        generate-config)
            stage_generate_config
            ;;
        bootstrap)
            stage_bootstrap
            ;;
        deploy)
            stage_deploy
            ;;
        post-fix)
            log_start "post-fix"
            local ip
            ip=$(guest_get_ip)
            kolla_post_deploy_fix "${ip}"
            ;;
        start)
            log_start "start"
            zsh "${LAB_PROJECT_ROOT}/scripts/start-openstack.zsh" --start-vm
            ;;
        stop)
            log_start "stop"
            zsh "${LAB_PROJECT_ROOT}/scripts/stop-openstack.zsh" --shutdown-vm
            ;;
        verify)
            stage_verify
            ;;
        status)
            status_show
            ;;
        logs)
            log_show_latest
            ;;
        destroy)
            require_root
            cleanup_destroy
            ;;
        rebuild)
            require_root
            cleanup_destroy
            stage_preflight
            stage_create_vm
            stage_wait
            stage_configure
            stage_install_kolla
            stage_generate_config
            stage_bootstrap
            stage_deploy
            stage_verify
            ;;
        build)
            stage_preflight
            stage_create_vm
            stage_wait
            stage_configure
            stage_install_kolla
            stage_generate_config
            stage_bootstrap
            stage_deploy
            stage_verify
            ;;
        tofu-init)
            log_start "tofu-init"
            zsh "${LAB_PROJECT_ROOT}/scripts/tofu-init.zsh"
            ;;
        tofu-plan)
            log_start "tofu-plan"
            zsh "${LAB_PROJECT_ROOT}/scripts/tofu-plan.zsh" "${2:-}"
            ;;
        tofu-apply)
            log_start "tofu-apply"
            zsh "${LAB_PROJECT_ROOT}/scripts/tofu-apply.zsh" "${2:-}"
            ;;
        tofu-destroy)
            log_start "tofu-destroy"
            zsh "${LAB_PROJECT_ROOT}/scripts/tofu-destroy.zsh"
            ;;
        tofu-status)
            log_start "tofu-status"
            zsh "${LAB_PROJECT_ROOT}/scripts/tofu-status.zsh"
            ;;
        *)
            log_error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
