# 環境識別子
variable "env" {}
# AWSアカウントID
variable "aws_account" {}
# AWSアクセスキー
variable "aws_access_key" {}
# AWSシークレットキー
variable "aws_secret_key" {}
# フロント資材のデプロイ用ユーザーのアクセスキー生成用GPG鍵
variable "front_app_deployer_gpg" {}