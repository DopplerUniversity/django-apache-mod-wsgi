FROM python:3.9-slim-buster

ENV PYTHONUNBUFFERED 1
ENV PYTHONDONTWRITEBYTECODE 1

# Install Doppler CLI and related dependencies
RUN apt-get -qq update && apt-get install -y apt-transport-https ca-certificates curl gnupg jq && \
curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' |  apt-key add - && \
echo "deb https://packages.doppler.com/public/cli/deb/debian any-version main" | tee /etc/apt/sources.list.d/doppler-cli.list && \
apt-get update &&  apt-get install doppler

# Install Apache and related dependencies
RUN apt-get install --yes apache2 apache2-dev libapache2-mod-wsgi-py3 && \
    apt-get clean && \
    apt-get remove --purge --auto-remove -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

COPY requirements*.txt .
RUN pip install --quiet --no-cache-dir --upgrade pip && \
    pip install --quiet --no-cache-dir -r requirements.txt

COPY src/ ./

COPY apache-doppler-start /usr/local/bin/
COPY wsgi.conf /etc/apache2/sites-enabled/000-default.conf

EXPOSE 80 443

CMD ["apache-doppler-start"]
