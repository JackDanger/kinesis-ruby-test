#!/bin/sh

set -eo pipefail

if [ -z $AWS_ACCESS_KEY_ID ]; then
  echo "The AWS credentials aren't in your environment, asking for them directly:"
  echo "AWS_ACCESS_KEY_ID: \c"
  read AWS_ACCESS_KEY_ID
fi
if [ -z $AWS_SECRET_ACCESS_KEY ]; then
  echo "AWS_SECRET_ACCESS_KEY: \c"
  read AWS_SECRET_ACCESS_KEY
fi


docker pull ruby:2.5
docker run -it \
  -v $(PWD):/app \
  -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
  -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
  ruby:2.5 \
  sh -c "cd /app && bundle && bundle exec ruby app.rb"
