# How to Set Environment Variables for a Python Django Application using Apache and mod_wsgi in Docker

In this guide, you'll learn how to inject secrets as environment variables for Python WSGI applications using Apache and mod_wsgi in Docker.

The [sample application]([https://github.com/DopplerUniversity/django-apache-mod-wsgi]) uses Docker and Django in order to produce a complete working example but the same concepts and steps apply whether you're using a Virtual Machine or a different Python framework.

Prefer just to read the code? Head to the accompanying repository at [https://github.com/DopplerUniversity/django-apache-mod-wsgi](https://github.com/DopplerUniversity/django-apache-mod-wsgi)

## Environment Variables, Apache and mod_wsgi

When hosting a Python WSGI compatible framework like Django in Apache with mod_wsgi, the only environment variables populated in the `os.environ` dictionary are those that exist in the environment of the script that starts Apache. But instead of having to mess with Apache's service manager settings (e.g. `systemd` or `systemctl`), there's a better way.

Most Apache distrbutions provide a shell script specifically for the purpose of setting environment variables that will be made available to modules such as `mod_wsgi`.

It's then a matter of knowing the location of this shell script as it can be different depending on the Linux distribtion. For example:

- Debian/Ubuntu: `/etc/apache2/envvars`
- CentOS: `/etc/sysconfig/httpd`

This might seem strange, but bear in mind that Apache is simply an open source application that isn't necessarily opinionated about such as things. In any case, it's the Linux distribution maintainers that need to decide how Apache will be installed, managed, and configured. As a result, there's bound to be some differences.

We'll be using the script at `/etc/apache2/envvars` as the [`python:3.9-slim-buster` Docker image](https://github.com/docker-library/python/blob/master/3.9/buster/slim/Dockerfile) is Debian based.

## Appending App Config and Secrets to the Environment Variables File

Essentially, it boils down to fetching the secrets as key / value pairs and writing them to the `envvars` file in the typical `export MY_VAR="value"` format. But where from and how do we fetch the app config and secrets to populate that file with?

As I'm the Developer Advocate for Doppler, I'll start with a [Doppler CLI](https://docs.doppler.com/docs/enclave-installation) example, but the mechanics of "fetch secrets, then append to file" can easily be adapted for other config and secret sources.

First you would need to set up your project in Doppler so it contains the required app config and secrets. If you want to follow along, you can create a test project in Doppler:

<a href="https://dashboard.doppler.com/workplace/template/import?template=https%3A%2F%2Fgithub.com%2FDopplerUniversity%2Fdjango-apache-mod-wsgi%2Fblob%2Fmain%2Fdoppler-template.yaml"/>
    <img src="https://raw.githubusercontent.com/DopplerUniversity/app-config-templates/main/doppler-button.svg" alt="Import to Doppler" />
</a>

Then use the Doppler CLI inside the Docker container to fetch the secrets (requires a `DOPPLER_TOKEN` environment variable with a [Service Token](https://docs.doppler.com/docs/enclave-service-tokens) value):

```sh
# Transform JSON key:value pairs into export statements using jq
if [ -n "$DOPPLER_TOKEN" ]; then
    echo '[info]: Appending environment variables to /etc/apache/envvars using Doppler CLI'
    doppler secrets download --no-file | jq -r $'. | to_entries[] | "export \(.key)=\'\(.value)\'"' >> /etc/apache2/envvars
fi
```

Notice that I've used single quotes, not double quotes around the values? That's because it gives you the flexibility of storing secrets with double quotes such as JSON in Doppler. This is awesome for being able to set the [`ALLOWED_HOSTS` value dynamically for each environment](https://github.com/DopplerUniversity/django-apache-mod-wsgi/blob/main/src/doppler/settings.py#L29).

You could also use a `.env` file but [I wouldn't recommend it](https://www.doppler.com/blog/the-triumph-and-tragedy-of-env-files) and a [secrets manager](https://www.doppler.com/blog/what-is-a-secrets-manager) of any description is a better choice. But that aside, here is how you could do it with an `.env` file:

```sh
if [ -f "$PWD/.env" ]; then
    echo '[info]: Appending environment variables to /etc/apache/envvars from .env file'
    cat "$PWD/.env" >> /etc/apache2/envvars
fi
```

Now that we know how to pass environment variables from Apache to mod_wsgi, let's move onto getting this working in Docker.

## Docker Configuration for Apache and mod_wsgi

Let's breakdown the task of configuring a Python Django Application using Apache and mod_wsgi in Docker into four steps:

1. Custom Start Script
2. Apache Site Config
3. Dockerfile
4. Docker Build

If you only want to see the working code examples, head to the accompanying repository at [https://github.com/DopplerUniversity/django-apache-mod-wsgi](https://github.com/DopplerUniversity/django-apache-mod-wsgi)

As this isn't a Docker or Apache tutorial, I won't be diving too deeply into the `Dockerfile` or Apache site config file, but if you've got questions, head over to the [Doppler community forum](https://community.doppler.com/) and I'll be able to help you there.

### 1. Custom Start Script

Running your application in Docker is usually a case of setting `CMD` e.g. `CMD ["python", "src/app.py"]`.  But it's trickier here as we first need to append the environment variables to `/etc/apache2/envvars` before running Apache.

As this will require multiple commands, we'll create a custom script that would look something like the following:

```sh
#!/bin/bash

# apache-doppler-start

set -e

echo 'ServerName localhost' >> /etc/apache2/apache2.conf # Silence FQDN warning

# Doppler CLI
if [ -n "$DOPPLER_TOKEN" ]; then
    echo '[info]: Appending environment variables to /etc/apache/envvars from Doppler CLI'
    doppler secrets download --no-file | jq -r $'. | to_entries[] | "export \(.key)=\'\(.value)\'"' >> /etc/apache2/envvars
fi

## Mounted .env file
if [ -f "$PWD/.env" ]; then
    echo '[info]: Appending environment variables to /etc/apache/envvars from .env file'
    cat "$PWD/.env" >> /etc/apache2/envvars
fi

# Run Apache
apache2ctl -D FOREGROUND
```

### 2. Apache Site Config

Here is an example Apache site config file for a Django application that replaces default provided by Apache on Debian and Ubuntu.

This is by no means a battle-hardened example I would put into production, but is sufficient for the purposes this tutorial.

```
# wsgi.conf

<VirtualHost *:80>
    ServerName django-apache-mod-wsgi
    ServerAlias django-apache-mod-wsgi
    ServerAdmin webmaster@doppler

    # Defining `WSGIDaemonProcess` and `WSGIProcessGroup` triggers daemon mode
    WSGIDaemonProcess django-apache-mod-wsgi processes=2 threads=15 display-name=%{GROUP} python-path=/usr/local/lib/python3.9/site-packages:/usr/src/app    
    WSGIProcessGroup django-apache-mod-wsgi
    WSGIScriptAlias / /usr/src/app/doppler/wsgi.py

    <Directory /usr/src/app/doppler/>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    # Redirect all logging to stdout for Docker
    LogLevel INFO
    ErrorLog /dev/stdout
    TransferLog /dev/stdout
</VirtualHost>
```

# 3. Dockerfile

The `Dockerfile` is reasonably straightforward:

```Dockerfile
FROM python:3.9-slim-buster

ENV PYTHONUNBUFFERED 1
ENV PYTHONDONTWRITEBYTECODE 1

# Install Doppler CLI and related dependencies
RUN apt-get -qq update && apt-get install -y apt-transport-https ca-certificates curl gnupg jq && \
curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' |  apt-key add - && \
echo "deb https://packages.doppler.com/public/cli/deb/debian any-version main" | tee /etc/apt/sources.list.d/doppler-cli.list && \
apt-get -qq update && apt-get install doppler

# Install Apache and related dependencies
RUN apt-get install --yes apache2 apache2-dev libapache2-mod-wsgi-py3 && \
    apt-get clean && \
    apt-get remove --purge --auto-remove -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

COPY requirements*.txt .
RUN pip install --quiet --no-cache-dir --upgrade pip && \
    pip install --quiet --no-cache-dir -r requirements.txt

# Application source
COPY src/ ./

# Custom CMD script
COPY apache-doppler-start /usr/local/bin/

# Apache site config
COPY wsgi.conf /etc/apache2/sites-enabled/000-default.conf

EXPOSE 80 443

# https://httpd.apache.org/docs/2.4/stopping.html#gracefulstop
STOPSIGNAL SIGWINCH

CMD ["apache-doppler-start"]
```

### 4. Docker Build

With all the pieces in place, we can build the Docker image (clone the [sample repository](https://github.com/DopplerUniversity/django-apache-mod-wsgi) to follow along):

```sh
docker image build -t django-apache-mod-wsgi:latest .
```

Now we're ready to run the container!

## Running the Django Application with Apache and mod_wsgi in Docker

We'll start with a Doppler example, then with an `.env` file.

### Doppler

With Doppler, you'll first need to set a `DOPPLER_TOKEN` enviroment variable to the value of a [Service Token](https://docs.doppler.com/docs/enclave-service-tokens). This is what provides read-only access to a specific Doppler config in production environments.

Usually, this would be securely set by your deployment environment (e.g. GitHub Action Secret) but for completeness an simplicity, we'll set it manually below:

```sh
export DOPPLER_TOKEN="dp.st.xxxx" # Service token value created from Doppler dashboard
```

Let's run the container (with development friendly options):

```sh
docker container run \
  -it \
  --init \
  --name doppler-apache-mod-wsgi \
  --rm \
  -p 8080:80 \
  -e DOPPLER_TOKEN="$DOPPLER_TOKEN" \
  django-apache-mod-wsgi
```

### .env File

To run the `.env` file version, we'll use `sample.env` from the [sample repository](https://github.com/DopplerUniversity/django-apache-mod-wsgi):

```sh
docker container run \
  -it \
  --init \
  --name dotenv-apache-mod-wsgi \
  --rm \
  -v $(pwd)/sample.env:/usr/src/app/.env \
  -p 8080:80 \
  django-apache-mod-wsgi
```

## Summary

Nice work in making it to the end!

Now you know how to configure Python applications hosted with Apache and mod_wsgi running in Docker using environment variables for app configuration and secrets.