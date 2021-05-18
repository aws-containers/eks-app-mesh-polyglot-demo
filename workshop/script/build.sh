cd workshop
#aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/u2g6w7p2
PROJECT_NAME=eks-workshop-demo
export APP_VERSION=1.0
for app in catalog_detail product_catalog frontend_node; do
  TARGET=public.ecr.aws/u2g6w7p2/$PROJECT_NAME/$app:$APP_VERSION
  docker build -t $TARGET apps/$app
  docker push $TARGET
done