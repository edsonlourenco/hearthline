# AWS CLI

MiniStack speaks the AWS API. The CLI does not need a special build. It needs an endpoint, a region, path-style S3, and any credentials. Hearthline uses the public lab pair `test` / `test`.

## On the server

A root install configures the home directory of `SUDO_USER`, which is the person who ran `sudo ./install.sh`.

It always writes the profile `hearthline`:

```ini
[profile hearthline]
region = us-east-1
output = json
endpoint_url = http://192.168.11.254:4566
s3 =
    addressing_style = path
```

Path-style addressing matters. The CLI's default virtual-hosted style sends `bucket.localhost`, and MiniStack expects the bucket in the path.

The `default` profile is updated only when it is missing or when its access key is `test`. A real key, anything other than `test`, is left exactly as it was. You then choose the lab per command:

```bash
aws --profile hearthline sts get-caller-identity
aws --profile hearthline s3 mb s3://lab-bucket
aws --profile hearthline sqs create-queue --queue-name lab-queue
```

A successful identity call looks like this:

```json
{
    "UserId": "000000000000",
    "Account": "000000000000",
    "Arn": "arn:aws:iam::000000000000:root"
}
```

A 12-digit access key is treated by MiniStack as the account id. The key `test` is not 12 digits, so the account stays `000000000000`. Teams that want isolated state on one shared lab can use a different 12-digit key per person. Hearthline itself stays on `test` unless you change the unit environment and reinstall.

## On another computer

The installer does not reach into other machines. Each one needs the same endpoint:

```bash
aws configure set aws_access_key_id test --profile hearthline
aws configure set aws_secret_access_key test --profile hearthline
aws configure set region us-east-1 --profile hearthline
aws configure set endpoint_url http://<lan-address>:4566 --profile hearthline
aws configure set s3.addressing_style path --profile hearthline
```

`hearthline endpoint` on the server prints the address to copy.

SDKs honour `AWS_ENDPOINT_URL`. On the server you can `source /etc/hearthline/env.sh` before Terraform, CDK, or a boto3 script. Those tools still need their own endpoint settings when they do not read `AWS_ENDPOINT_URL`. MiniStack's documentation shows the Terraform `endpoints` block. Point every service you use at the same URL.

## Installing the CLI

If `aws` is already on `PATH`, Hearthline does not replace it. If it is missing, the installer downloads AWS CLI v2 from `awscli.amazonaws.com` and runs the official `aws/install` into `/usr/local`. A rootless install puts it under `~/.local` instead. A tiny `awscliv2.zip` that is actually an HTML redirect is not an installer. Hearthline always downloads the archive itself.
