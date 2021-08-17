SHELL=/bin/bash
VENVDIR?=${HOME}/.virtualenvs
WORKDIR?=$(shell basename "$$PWD")
VENV?=$(VENVDIR)/$(WORKDIR)/bin
PYTHON?=$(VENV)/python
ACTIVATE?=$(VENV)/activate

create-virtual-env:
	mkdir -p ~/.virtualenvs && \
	python3 -m venv $(VENVDIR)/$(WORKDIR) && \
	. $(ACTIVATE) && \
	pip install --upgrade pip setuptools && \
	pip install -r requirements-dev.txt

activate:
	. $(ACTIVATE)
lint:
	flake8 --ignore E501 src

format:
	black --skip-string-normalization --line-length 120 src

CONTAINER_NAME=django-apache-mod-wsgi
IMAGE_NAME=django-apache-mod-wsgi

build:
	docker image build -t $(IMAGE_NAME):latest .

# Requires DOPPLER_TOKEN environment variable
# Can supply optional CMD to override default, e.g. `make run CMD=bash`
run-doppler:
	docker container run \
		-it \
		--init \
		--rm \
		--name $(CONTAINER_NAME) \
		-p 8080:80 \
		-e DOPPLER_TOKEN=${DOPPLER_TOKEN} \
		$(IMAGE_NAME) $(CMD)

run-dotenv:
	docker container run \
		-it \
		--init \
		--rm \
		--name $(CONTAINER_NAME) \
		-v $$(pwd)/sample.env:/usr/src/app/.env \
		-p 8080:80 \
		$(IMAGE_NAME) $(CMD)

exec:
	docker container exec -it $(CONTAINER_NAME) bash
