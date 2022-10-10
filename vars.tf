variable "AWS_REGION" {
  default = "eu-central-1"
}

variable "ACCESS_KEY" {
  default = "************"
}

variable "SECRET_KEY" {
  default = "**************"
}

variable "ECS_INSTANCE_TYPE" {
  default = "t2.micro"
}

variable "ECS_AMI" {
  type = map(string)
  default = {
    eu-central-1 = "ami-05ff5eaef6149df49"
  }
}
