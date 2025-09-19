# DevOps Tools Installer

Automate the installation and uninstallation of essential DevOps tools on your Linux machine with this interactive Bash script. Supports Ubuntu/Debian, CentOS/RHEL, and Fedora.

## Features
- **Install/Uninstall**: Choose tools to install or remove interactively
- **Supported Tools**: Docker, Kubernetes (kubectl), Terraform, Jenkins, AWS CLI, Azure CLI, Google Cloud SDK, Helm, Grafana, GitLab Runner, Vault, Consul, Istio, OpenShift, Minikube, Packer, Vagrant, Lynis, Maven, Gradle, Dependency-Check, Java, Git, Ansible, Prometheus, Node Exporter
- **Tool Group Presets**: Quickly select toolsets for CI/CD, Kubernetes, Cloud, Monitoring, Infrastructure
- **Parallel Installation**: Option to install tools in parallel for faster setup
- **Post-Install Configuration**: Enables and starts services like Docker, Jenkins, Grafana
- **Update/Upgrade**: Optionally update system packages before installation
- **Profiles & CLI Args**: Use saved profiles or override tool/version via command-line
- **Offline Mode**: Use pre-downloaded packages if available
- **Remote Install**: Install tools on remote machines via SSH
- **Security Checks**: Verifies root/sudo, checks dependencies, validates checksums
- **Setup Report**: Generates a Markdown report of installed tools and system info
- **Smart Recommendations**: Suggests toolsets based on your role (DevOps, SRE, Cloud Architect)

## Usage

```sh
chmod +x Dev-Ops-tools_install.sh
./Dev-Ops-tools_install.sh
```

Follow the interactive prompts to:
- Select your Linux distribution
- Choose install or uninstall
- Pick tools (or use a preset)
- Optionally update/upgrade system packages
- Optionally install in parallel

### Command-Line Options
You can automate or override selections using CLI arguments:
- `--profile=NAME`         Use a saved profile (e.g., ci_cd, k8s, cloud)
- `--tool=TOOL`            Install a specific tool (e.g., docker)
- `--version=VERSION`      Override tool version (e.g., terraform)
- `--offline`              Use offline packages
- `--remote=USER@HOST`     Install on remote machine
- `--dry-run`              Show planned actions only
- `--help`                 Show help menu

Example:
```sh
./Dev-Ops-tools_install.sh --profile=ci_cd --dry-run
```

## Supported Linux Distributions
- Ubuntu/Debian
- CentOS/RHEL
- Fedora

## Tool Group Presets
- **ci_cd**: jenkins git maven gradle
- **k8s**: kubectl helm minikube istio openshift
- **cloud**: awscli azurecli gcloud
- **monitoring**: grafana prometheus node_exporter
- **infra**: terraform packer vagrant ansible

## Advanced Features
- **Config Save/Load**: Remembers your last choices in `.devops-installer-config`
- **Disk Space Estimation**: Estimates disk usage before install
- **Service Validation**: Checks if key services are running
- **Cleanup**: Removes configs and disables services on uninstall
- **Logging**: Actions are logged to `installer.log`
- **Telemetry (Opt-in)**: Anonymous usage reporting (stub)

## Requirements
- Bash
- curl, unzip, gnupg, whiptail (auto-installed if missing)
- Root/sudo privileges

## Suggestions
- Consider running in a Docker container for isolated installs
- Use the dry-run mode to preview actions before making changes
- Review the generated `setup_report.md` after installation
- For bulk installs, use parallel mode for speed
- Use tool group presets for common DevOps roles

## Help & Documentation
Run with `--help` for usage instructions:
```sh
./Dev-Ops-tools_install.sh --help
```

---

**Author:** RajaChowdary tech

Feel free to contribute or suggest improvements!
