#! /bin/sh

# Verify ENV var inputs
if [ -n "$RANCHER_API_KEY" ]; then
    echo "RANCHER_API_KEY: ** Provided **"
else
    echo "RANCHER_API_KEY: Missing"
    echo .
    echo "This script requires the Rancher API Key to be Provided"
    echo .
    echo "The Rancher API Key needs to have sufficent privileges for"
    echo "the inputed Rancher Environment $[RANCHER_ENV}"
    exit 1
fi

if [ -n "${RANCHER_ENV}" ]; then
    echo "RANCHER_ENV: ${RANCHER_ENV}"
else
    echo "RANCHER_ENV: Missing"
    echo .
    echo "This is a mandatory ENV var"
    echo .
    echo "Must match an existing Rancher Environment configured on the Rancher Server"
    exit 1;
fi

if [ -n "${RANCHER_HOST}" ]; then
    echo "RANCHER_HOST: ${RANCHER_HOST}"
else
    echo "RANCHER_HOST: Missing"
    echo .
    echo "This is a mandatory ENV var"
    echo .
    echo "Must be the HOST or IP of the Rancher Server or Rancher Server Load Balancer"
    exit 1;
fi

if [ -n "${RANCHER_TAGS}" ]; then
    echo "RANCHER_TAGS: ${RANCHER_TAGS}"
else
    echo "RANCHER_TAGS: Missing"
    echo .
    echo "This is an optional ENV var, so no harm done"
    echo .
    echo "If Populated it must be in the form:"
    echo "key1=val1&key2=val2"
fi

if [ "${RANCHER_HTTP_SCHEME}" == "http" ]; then
    HTTP_SCHEME="http"
elif [ "${RANCHER_HTTP_SCHEME}" == "HTTP" ]; then
    HTTP_SCHEME="http"
else
    HTTP_SCHEME="https"
fi

# Check that the required locations have been Volumed in
if [ -S "/var/run/docker.sock" ]; then
    echo "Socket '/var/run/docker.sock' has been volumed in"
else
    echo "The container must have be run with the argument '-v /var/run/docker.sock:/var/run/docker.sock'"
    exit 1
fi

if [ -d "/var/lib/rancher" ]; then
    echo "Directory '/var/lib/rancher' has been volumed in"
else
    echo "The container must have be run with the argument '-v /var/lib/rancher:/var/lib/rancher'"
    exit 1
fi

if [ -f "/var/lib/rancher/engine/docker" ]; then
    echo "Found the 'docker' executable"
    DOCKER=/var/lib/rancher/engine/docker
elif [ -f "/bin/docker" ]; then
    echo "Found the 'docker' executable"
    DOCKER=/bin/docker
else
    echo "Unable to find 'docker' executable"
    exit 1
fi

# Get Project ID
PROJECT_ID=$(curl -s -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/projects" | jq -r ".data[] | select( .name == \"${RANCHER_ENV}\" ) | .id")
echo "PROJECT_ID: ${PROJECT_ID}"

# Get Docker Image
DOCKER_IMAGE=$(curl -s -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/registrationtokens?projectId=${PROJECT_ID}" | jq -r '.data[0].image')
echo "DOCKER_IMAGE: ${DOCKER_IMAGE}"

# Get Token
TOKEN=$(curl -s -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/registrationtokens?projectId=${PROJECT_ID}" | jq -r '.data[0].token')
echo "TOKEN ${TOKEN}"

# Generate Token if required
if [ "${TOKEN}" == "null" ]; then
    echo "Generate new Registration Token"
    curl -s -X POST -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/registrationtokens?projectId=${PROJECT_ID}"
    sleep 5

    TOKEN=$(curl -s -u ${RANCHER_API_KEY} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/registrationtokens?projectId=${PROJECT_ID}" | jq -r '.data[0].token')
    echo "TOKEN ${TOKEN}"
fi

# Update the rancher agent
echo "Pull Docker Image update for ${DOCKER_IMAGE}"
${DOCKER} pull ${DOCKER_IMAGE}

# start the ranger/agent container
if [ -n "${RANCHER_TAGS}" ]; then
    ${DOCKER} run -d --privileged -e CATTLE_HOST_LABELS="${RANCHER_TAGS}" -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/rancher:/var/lib/rancher ${DOCKER_IMAGE} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/scripts/${TOKEN}"
else
    ${DOCKER} run -d --privileged -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/rancher:/var/lib/rancher ${DOCKER_IMAGE} "${HTTP_SCHEME}://${RANCHER_HOST}/v1/scripts/${TOKEN}"
fi
