# cloud_gpu

A set of simple and effective Bash scripts to start, stop, and connect to GPU-enabled cloud compute instances on both AWS and Google Cloud Platform. These scripts help you manage your resources and control costs by only running your instances when you need them.

## 🚀 Quick Start

1.  **Configure Your Cloud Provider**: Ensure you have the respective command-line tools installed and configured with your credentials.

      * **AWS CLI**: Run `aws configure`.
      * **Gcloud CLI**: Run `gcloud auth login` and `gcloud config set project [YOUR_PROJECT_ID]`.

2.  **Run the Setup Script**: The `setup.sh` script will guide you through the process of installing the necessary CLI and creating a configuration file.

    ```bash
    ./setup.sh [aws|gcp]
    ```

    The script will prompt you for your instance details and save them to a `.env` file, which is used by the other scripts. It also adds aliases to your shell's RC file for easy access.

3.  **Run the Scripts**: You can use the full script names or the aliases created by the setup script to manage your instance.

    To start your instance and connect:

    ```bash
    # Using the script name directly
    ./gcloud-start.sh
    # or
    ./aws-start.sh

    # Using the alias
    gcloud-start
    # or
    aws-start
    ```

    To stop your instance:

    ```bash
    # Using the script name directly
    ./gcloud-stop.sh
    # or
    ./aws-stop.sh

    # Using the alias
    gcloud-stop
    # or
    aws-stop
    ```

    You can also provide arguments to override the values from the `.env` file:

    ```bash
    ./gcloud-start.sh my-other-instance us-central1-c
    ```

-----

## ⚙️ Scripts

This project contains a setup script, a cleanup script, and two pairs of utility scripts for managing cloud instances.

### `setup.sh` and `clean.sh`

  * **`setup.sh`**: The main setup script. It automates the following steps:

      * Installs the required cloud CLI (`aws` or `gcloud`) if not present.
      * Prompts you for your instance's name, zone, and (for AWS) PEM file path.
      * Creates a `.env` configuration file with the provided details.
      * Adds provider-specific aliases (e.g., `gcloud-start`, `aws-start`) to your shell's RC file (`~/.bashrc` or `~/.zshrc`) for easy access.

  * **`clean.sh`**: A utility to clean up the project configuration. It can remove the `.env` file and the aliases from your shell's RC file.

### `gcloud-start.sh` and `gcloud-stop.sh`

These scripts are for managing **Google Cloud Compute Engine** instances. They use the `gcloud` CLI, which automatically handles SSH key management.

  * `gcloud-start.sh`: Starts the specified instance and connects via SSH.
  * `gcloud-stop.sh`: Stops the specified instance to avoid unnecessary compute charges.

### `aws-start.sh` and `aws-stop.sh`

These scripts are for managing **AWS EC2** instances. They use the `aws` CLI for instance management and standard `ssh` for connection.

  * `aws-start.sh`: Starts the specified EC2 instance, waits for it to become ready, and then connects via SSH using the provided PEM key.
  * `aws-stop.sh`: Stops the specified EC2 instance to avoid unnecessary compute charges. Your file system is retained.

-----

## 📚 Notes on Usage and Billing

  * **Cost Management**: Stopping an instance avoids compute charges but you may still incur costs for any attached storage (EBS volumes for AWS, or persistent disks for GCP).
  * **Dynamic IPs**: The scripts are designed to work with dynamic IP addresses. When you start an instance, a new public IP is assigned, which the script automatically retrieves. This allows you to avoid the cost of an Elastic IP (AWS) or a static IP (GCP).
  * **Permissions**: Ensure your SSH private key (`.pem`) file for AWS has the correct permissions (`chmod 400`). The `aws-start.sh` script includes a check for this.
  * **Configuration**: The scripts will first check for command-line arguments and then fall back to the values in the `.env` configuration file. If neither is present, the script will fail with a clear error message.