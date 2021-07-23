#!/usr/bin/env bash
set -eu
set -o pipefail
# set -x
###
# A shell script to be used as a Terraform external datasource to fetch AMI as created by ImageBuilder pipeline.
# Can't use a normal aws_ami datasource as that throws an error if there's no result, leaving a chicken&egg situation.
#
# Usage:
# data "external" "imagebuilder_ami" {
#   program = ["bash", "${path.module}/files/jq-ext-latest-imagebuilder-arn.sh"]
#   query = {
#     JQ_AWS_REGION = "eu-west-1"
#     JQ_IMAGE_NAME = "imagebuilder-project-qa"
#   }
# }
#
# Result:
#   data.external.imagebuilder_ami.result = {
#     "region": "eu-west-1",
#     "image": "ami-0ddadc965123456789",
#     "name": "project-qa-2021-07-06T21-35-16.057Z",
#     "description": "Terraform and EC2 ImageBuilder generated AMI for project",
#     "accountId": "123456789012"
#   }
#
# Unit Testing:
#   echo '{"JQ_AWS_REGION": "eu-west-1", "JQ_IMAGE_NAME": "imagebuilder-project-qa"}' | ./files/jq-ext-latest-imagebuilder-arn.sh
###

# Use JQ's @sh to escape the datasource arguments & eval to set env vars
eval "$(jq -r '@sh "JQ_AWS_REGION=\(.JQ_AWS_REGION) JQ_IMAGE_NAME=\(.JQ_IMAGE_NAME)"')"
RET=$(
  aws imagebuilder list-images  --output json --owner 'Self'  --region "${JQ_AWS_REGION}"                             | \
      jq -r --arg JQ_IMAGE_NAME "${JQ_IMAGE_NAME}" '.imageVersionList |
                                                      map(select(.name == $JQ_IMAGE_NAME)) |
                                                      max_by(.dateCreated).arn'                                       | \
      xargs -n1 -I% aws imagebuilder --output json get-image --image-build-version-arn % --region "${JQ_AWS_REGION}"  | \
      jq --exit-status --arg JQ_AWS_REGION "${JQ_AWS_REGION}"                                                           \
          '.image.outputResources.amis[] | select( .region == $JQ_AWS_REGION )' || true
)
[[ -n "${RET}" ]] && echo "${RET}" || echo '{}'
