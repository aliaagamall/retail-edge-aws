environment = "dev"

alb_deletion_protection     = false
rds_skip_final_snapshot     = true
rds_backup_retention_period = 0
rds_instance_class          = "db.t3.micro"

redis_node_type             = "cache.t3.micro"

app_instance_type           = "t3.micro"

asg_min_size                = 2
asg_max_size                = 4
asg_desired_capacity        = 2