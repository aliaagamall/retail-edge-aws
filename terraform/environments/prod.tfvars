environment = "prod"

alb_deletion_protection     = true
rds_skip_final_snapshot     = false
rds_backup_retention_period = 7
rds_instance_class          = "db.t3.small"

redis_node_type             = "cache.t3.small"

app_instance_type           = "t3.small"

asg_min_size                = 2
asg_max_size                = 10
asg_desired_capacity        = 3