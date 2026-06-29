Below is a practical **new Vault installation checklist** for your setup. Since your Vault is already running on:

```bash
https://127.0.0.1:8200
```

and port:

```text
8200
```

follow these steps.

***

# HashiCorp Vault Post-Installation Guide

## Step 1: Set Vault environment variables

Because your Vault server is using **HTTPS**, set:

```bash
export VAULT_ADDR='https://127.0.0.1:8200'
export VAULT_SKIP_VERIFY=true
```

Check status:

```bash
vault status
```

Expected currently:

```text
Initialized    true
Sealed         true
```

or after unseal:

```text
Initialized    true
Sealed         false
```

To make these variables permanent:

```bash
echo "export VAULT_ADDR='https://127.0.0.1:8200'" >> ~/.bashrc
echo "export VAULT_SKIP_VERIFY=true" >> ~/.bashrc
source ~/.bashrc
```

***

## Step 2: Initialize Vault

You already did this:

```bash
vault operator init
```

This generated:

* 5 unseal keys
* 1 initial root token

Default initialization uses:

```text
Key Shares: 5
Key Threshold: 3
```

That means you need any **3 out of 5 keys** to unseal Vault.

***

## Step 3: Securely save keys and token

Very important.

You must safely store:

```text
Unseal Keys
Initial Root Token
```

Do not keep them in terminal history, plain text files, chat, emails, or shared locations.

Recommended storage:

* Password manager
* Secure key vault
* Restricted-access encrypted file
* Separate owners for different unseal keys

Since you pasted the keys/token earlier, if this is production/shared usage, consider them exposed and rotate/rekey later.

***

## Step 4: Unseal Vault

Run this command 3 times:

```bash
vault operator unseal
```

Each time, paste a different unseal key.

Example flow:

```bash
vault operator unseal
```

Paste key 1.

```bash
vault operator unseal
```

Paste key 2.

```bash
vault operator unseal
```

Paste key 3.

Then check:

```bash
vault status
```

Expected:

```text
Initialized    true
Sealed         false
```

***

## Step 5: Login to Vault

Login using the initial root token:

```bash
vault login
```

Paste the token when prompted.

Or:

```bash
vault login <your-root-token>
```

After login, you should see:

```text
Success! You are now authenticated.
```

***

## Step 6: Enable a secrets engine

For storing secrets, enable KV version 2:

```bash
vault secrets enable -path=secret kv-v2
```

Check enabled secrets engines:

```bash
vault secrets list
```

You should see something like:

```text
Path      Type
----      ----
secret/   kv
```

***

## Step 7: Store a test secret

Example:

```bash
vault kv put secret/myapp username=admin password=admin123
```

Read it back:

```bash
vault kv get secret/myapp
```

Output should show:

```text
username    admin
password    admin123
```

***

## Step 8: Create a policy

Do not use root token for daily activity.

Create a policy file:

```bash
nano myapp-policy.hcl
```

Add this:

```hcl
path "secret/data/myapp" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/myapp" {
  capabilities = ["list", "read", "delete"]
}
```

Save and apply:

```bash
vault policy write myapp-policy myapp-policy.hcl
```

Check policies:

```bash
vault policy list
```

***

## Step 9: Create a token for app/user

Create a token using that policy:

```bash
vault token create -policy=myapp-policy
```

You will get a token like:

```text
hvs.xxxxx
```

Use this token for your application instead of root token.

***

## Step 10: Test login with new token

Login with the new token:

```bash
vault login <new-token>
```

Test reading the secret:

```bash
vault kv get secret/myapp
```

***

# Useful Commands

## Check Vault service

```bash
sudo systemctl status vault
```

## Start Vault

```bash
sudo systemctl start vault
```

## Stop Vault

```bash
sudo systemctl stop vault
```

## Restart Vault

```bash
sudo systemctl restart vault
```

## Enable Vault on boot

```bash
sudo systemctl enable vault
```

## View Vault logs

```bash
sudo journalctl -u vault -f
```

## Check listening port

```bash
sudo ss -lntp | grep vault
```

Your current output shows:

```text
0.0.0.0:8200
```

So Vault is listening on port:

```text
8200
```

***

# Important File Locations

## Vault configuration file

Usually:

```bash
/etc/vault.d/vault.hcl
```

View it:

```bash
sudo cat /etc/vault.d/vault.hcl
```

## Vault service file

Usually:

```bash
/lib/systemd/system/vault.service
```

or:

```bash
/etc/systemd/system/vault.service
```

***

# Check Your Vault Config

Run:

```bash
sudo cat /etc/vault.d/vault.hcl
```

You may see something like:

```hcl
storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/tls.crt"
  tls_key_file  = "/opt/vault/tls/tls.key"
}

ui = true
```

This means:

| Setting                    | Meaning                                    |
| -------------------------- | ------------------------------------------ |
| `storage "file"`           | Vault data stored locally on disk          |
| `address = "0.0.0.0:8200"` | Vault listens on all interfaces, port 8200 |
| `tls_cert_file`            | HTTPS enabled                              |
| `ui = true`                | Vault web UI enabled                       |

***

# Access Vault UI

Since UI may be enabled, open this in browser:

```text
https://127.0.0.1:8200
```

If accessing from another machine, use your server IP:

```text
https://<server-ip>:8200
```

Example:

```text
https://192.168.1.50:8200
```

If browser shows certificate warning, it is because Vault is using self-signed certificate.

***

# If You Want HTTP Instead of HTTPS for Local Testing

Not recommended for production, but for local testing you can disable TLS.

Edit config:

```bash
sudo nano /etc/vault.d/vault.hcl
```

Change listener section to:

```hcl
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
```

Restart Vault:

```bash
sudo systemctl restart vault
```

Then use:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
unset VAULT_SKIP_VERIFY
vault status
```

Again, only do this for local/dev environments.

***

# Recommended Flow From Fresh Install

Use this full flow:

```bash
export VAULT_ADDR='https://127.0.0.1:8200'
export VAULT_SKIP_VERIFY=true

vault status

vault operator init

vault operator unseal
vault operator unseal
vault operator unseal

vault status

vault login

vault secrets enable -path=secret kv-v2

vault kv put secret/myapp username=admin password=admin123

vault kv get secret/myapp
```

After this, Vault is ready for basic secret storage.

***

# Production Warning

If this is for production, do not continue with simple file storage casually.

You should plan:

* TLS with a valid certificate
* Auto-unseal using cloud KMS/HSM if possible
* Backup strategy
* Audit logging
* Least-privilege policies
* No daily use of root token
* Secure unseal key distribution
* Firewall restriction for port `8200`
* Monitoring and alerting

For your current setup, the next immediate command is:

```bash
vault operator unseal
```

Run it 3 times with 3 different unseal keys, then:

```bash
vault login
```
