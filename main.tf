provider "aws" {
  access_key = "var.ACCESS_KEY"
  secret_key = "var.SECRET_KEY"
  region = "var.AWS_REGION"
}

data "aws_availability_zones" "available" {
  state = "available"
}


resource "aws_ecs_cluster" "node_app" {
  name = "ECS cluster"
}


resource "aws_launch_configuration" "node_app_launch_config" {
  image_id      = "var.ECS_AMI"
  instance_type = "var.ECS_INSTANCE_TYPE"
  name = "NodeJS-app-LC"
  security_groups = [aws_security_group.ecs-securitygroup.id]
  iam_instance_profile = "aws_iam_instance_profile.ecs-ec2-role.id"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "node_app_autoscaling" {
  name                 = "NodeJS-app-ASG"
  launch_configuration = aws_launch_configuration.node_app_launch_config.name
  min_size             = 2
  max_size             = 4
  min_elb_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  health_check_type    = "ELB"
  load_balancers       = [aws_elb.node_app_elb.name]

  tag {
      key   = "Name"
      value = "Node_app_container"
      propagate_at_launch = true
    }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "Main"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "Public subnet 1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "Public subnet 2"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "Private subnet"
  }
}

resource "aws_db_subnet_group" "default" {
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name = "BD subnet group"
  }
}

resource "aws_db_instance" "mysql" {
  instance_class = "db.t3.micro"
  allocated_storage = 5
  db_name = "mydb"
  engine = "mysql"
  port = 3306
  username = "test"
  password = "test"
  security_group_names = [aws_db_security_group.rds_securitygroup.id]
  engine_version = "5.7"
  db_subnet_group_name = "aws_db_subnet_group.default.id"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "DB instance"
  }
}

resource "aws_elb" "node_app_elb" {
  name = "NodeJS-app-ELB"
  security_groups = [aws_security_group.elb_securitygroup.id]
  availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  listener {
    instance_port     = 3000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  listener {
    instance_port     = 3306
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  health_check {
    healthy_threshold   = 2
    interval            = 10
    target              = "HTTP:3000/"
    timeout             = 3
    unhealthy_threshold = 2
  }
  subnets = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id, aws_subnet.private_subnet.id]
  cross_zone_load_balancing = true

  tags = {
    Name = "My ELB"
  }
}

resource "aws_db_security_group" "rds_securitygroup" {
  name = "RDS_security_group"
  ingress {
    security_group_id = "aws_security_group.elb_securitygroup.id"
  }
}

resource "aws_security_group" "ecs-securitygroup" {
  vpc_id      = aws_vpc.main.id
  name        = "ecs"
  description = "security group for ecs"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.elb_securitygroup.id]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ecs"
  }
}

resource "aws_security_group" "elb_securitygroup" {
  vpc_id      = aws_vpc.main.id
  name        = "node_app_elb"
  description = "security group for ecs"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "myapp-elb"
  }
}

resource "aws_efs_file_system" "efs" {
  tags = {
    Name = "ECS-EFS"
  }
}

resource "aws_efs_mount_target" "efs_target_1" {
  file_system_id = "aws_efs_file_system.efs.id"
  subnet_id      = aws_subnet.public_subnet_1.id
}
resource "aws_efs_mount_target" "efs_target_2" {
  file_system_id = "aws_efs_file_system.efs.id"
  subnet_id      = aws_subnet.public_subnet_2.id
}


resource "aws_ecs_service" "ecs_service_1" {
  name = "ECS-service-myapp"
  cluster = "aws_ecs_cluster.node-app.id"
  iam_role = "aws_iam_role.ecs-service-role.arn"
  desired_count = 2
  launch_type = "EC2"
  task_definition = aws_ecs_task_definition.myapp-task.arn
  depends_on = [aws_iam_policy_attachment.ecs-service-attach]
  network_configuration {
    subnets = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  }
  load_balancer {
    elb_name = "aws_elb.node_app_elb.name"
    container_name = "myapp"
    container_port = 3000
  }
}

resource "aws_ecs_service" "ecs_service_2" {
  name            = "ECS-service-efs"
  cluster         = aws_ecs_cluster.node_app.id
  task_definition = aws_ecs_task_definition.efs_task.arn
  desired_count   = 2
  launch_type     = "EC2"

  network_configuration {
    subnets = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  }
  load_balancer {
    container_name = "nginx"
    container_port = 80
  }
}


resource "aws_ecs_task_definition" "efs_task" {
  family        = "efs-task"
  container_definitions = <<DEFINITION
[
  {
      "memory": 128,
      "portMappings": [
          {
              "hostPort": 80,
              "containerPort": 80,
              "protocol": "tcp"
          }
      ],
      "essential": true,
      "mountPoints": [
          {
              "containerPath": "/usr/share/nginx/html",
              "sourceVolume": "efs-html"
          }
      ],
      "name": "nginx",
      "image": "nginx"
  }
]
DEFINITION

  volume {
    name      = "efs-html"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.efs.id
      root_directory = "/efs-storage"
    }
  }
}

resource "aws_ecs_task_definition" "myapp-task" {
  family                = "myapp"
  container_definitions = <<DEFINITION
[
  {
    "essential": true,
    "memory": 256,
    "name": "myapp",
    "cpu": 256,
    "image": "181285487959.dkr.ecr.eu-central-1.amazonaws.com/myapp:v1",
    "workingDirectory": "/app",
    "command": ["npm", "start"],
    "portMappings": [
        {
            "containerPort": 3000,
            "hostPort": 3000
        }
    ]
  }
]
DEFINITION
}

resource "aws_ecr_repository" "myapp" {
  name = "NodeJS-app-image"
}



resource "aws_internet_gateway" "main-gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main_gw"
  }
}

resource "aws_route_table" "main-public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main-gw.id
  }

  tags = {
    Name = "Public_route_table"
  }
}

resource "aws_route_table_association" "public-1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.main-public.id
}

resource "aws_route_table_association" "public-2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.main-public.id
}


resource "aws_iam_role" "ecs-ec2-role" {
  name               = "ecs-ec2-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs-ec2-role" {
  name = "ecs-ec2-role"
  role = aws_iam_role.ecs-ec2-role.name
}

resource "aws_iam_role" "ecs-service-role" {
name = "ecs-service-role"
assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs-ec2-role-policy" {
name   = "ecs-ec2-role-policy"
role   = aws_iam_role.ecs-ec2-role.id
policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
              "ecs:CreateCluster",
              "ecs:DeregisterContainerInstance",
              "ecs:DiscoverPollEndpoint",
              "ecs:Poll",
              "ecs:RegisterContainerInstance",
              "ecs:StartTelemetrySession",
              "ecs:Submit*",
              "ecs:StartTask",
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage"
            ],
            "Resource": "*"
        }
    ]
}
EOF

}

resource "aws_iam_policy_attachment" "ecs-service-attach" {
  name       = "ecs-service-attach"
  roles      = [aws_iam_role.ecs-service-role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_autoscaling_policy" "elb_requests_policy" {
  autoscaling_group_name = "aws_autoscaling_group.node_app_autoscaling.name"
  name                   = "elb_requests_policy"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = "1"
  cooldown = "300"

}

resource "aws_cloudwatch_metric_alarm" "elb_requests_alarm" {
  alarm_name          = "request_alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  period = "120"
  threshold = "50"
  metric_name = "RequestCount"
  namespace = "AWS/ApplicationELB"

  dimensions = {
    "AutoScalingGroupName" = "aws_autoscaling_group.node_app_autoscaling.name"
  }
  alarm_actions = [aws_autoscaling_policy.elb_requests_policy.arn]
}

output "elb" {
  value = aws_elb.node_app_elb.dns_name
}


