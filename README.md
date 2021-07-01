# data-pipeline
Data Collection and Research Pipeline for various data sources



# Setup
1. Run `make firstrun` (installs pipenv and all requirements). NOTE: requires python 3.8 setup
2. Run `make` in the future which only installs pipenv requirements
3. In the future only change `Pipfile` and discuss with the team about impending changes
4. <Docker setup instructions here>

# Docker and Testing
TODO: @Nadim

# Local testing environment

Please follow following steps to setup local testing environment.
1. Install https://skaffold.dev/docs/install/
2. Install minikube https://minikube.sigs.k8s.io/docs/start/
3. Start minikube by running `minikube start`
4. Start Skaffold by running `skaffold dev --port-forward --tail` in this directory.

### Notes
* After step `4` skaffolld will automatically push containers to local kubernetes cluster (minikube). 
* Skaffold also watches files of this directory, upon any change  will trigger a docker build.
* Skaffold won't rebuild all docker images. Change in `web-frontend` directory will only trigger rebuild of docker image corresponding microservice.
* Skaffold will give a unified stream of log of all microservices in console.

You may see logs like
> Port forwarding service/backend-api-service in namespace default, remote port 5001 -> 127.0.0.1:5001

> Port forwarding service/web-frontend-service in namespace default, remote port 5000 -> 127.0.0.1:5002

Use the tailing urls (`127.0.0.1:5001`, `127.0.0.1:5002`) to access these service in browser.

# General Good Practices:
1. NEVER work off of master (unless first commits), make a feature branch
2. Once you are reasonably done with commits, push to github for a code review
3. Once we review them, you are good to merge
2. NEVER commit credentials and add them to the `.gitignore` file
