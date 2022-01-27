set -x -e

# DEVELOPMENT ALIAS VERSION
aws lambda get-alias \
  --function-name $DEPLOY_FUNCTION_NAME \
  --name $DEPLOY_ALIAS_NAME \
  > output.json
DEVELOPMENT_ALIAS_VERSION=$(cat output.json | jq -r '.FunctionVersion')

# CREATE ZIP FILE
cd function
zip ../function.zip *
cd ..

# UPDATE FUNCTION CODE
aws lambda update-function-code \
  --function-name $DEPLOY_FUNCTION_NAME \
  --zip-file fileb://function.zip \
  --publish \
  > output.json
LATEST_VERSION=$(cat output.json | jq -r '.Version')

# NO DEPLOYMENT NEEDED EXIT
if [[ $DEVELOPMENT_ALIAS_VERSION -ge $LATEST_VERSION ]]; then
  exit 0
fi

# CREATE APPSPEC FILE IN S3 BUCKET
cat > $DEPLOY_APPSPEC_FILE <<- EOM
version: 0.0
Resources:
  - myLambdaFunction:
      Type: AWS::Lambda::Function
      Properties:
        Name: "$DEPLOY_FUNCTION_NAME"
        Alias: "$DEPLOY_ALIAS_NAME"
        CurrentVersion: "$DEVELOPMENT_ALIAS_VERSION"
        TargetVersion: "$LATEST_VERSION"
EOM
aws s3 cp \
    $DEPLOY_APPSPEC_FILE \
    s3://$DEPLOY_BUCKET_NAME/$DEPLOY_APPSPEC_FILE

# CREATE DEPLOYMENT
REVISION=revisionType=S3,s3Location={bucket=$DEPLOY_BUCKET_NAME,key=$DEPLOY_APPSPEC_FILE,bundleType=YAML}
aws deploy create-deployment \
  --application-name $DEPLOY_APPLICATION_NAME \
  --deployment-group-name $DEPLOY_DEPLOYMENT_GROUP_NAME \
  --deployment-config-name CodeDeployDefault.LambdaAllAtOnce \
  --revision $REVISION
