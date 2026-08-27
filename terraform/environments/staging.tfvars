environment = "staging"

alb_deletion_protection     = false
rds_instance_class          = "db.t3.micro"
rds_allocated_storage       = 20
rds_backup_retention_period = 7
rds_multi_az                = true
rds_skip_final_snapshot     = false
rds_deletion_protection     = true

redis_node_type             = "cache.t3.micro"

app_instance_type           = "t3.micro"

asg_min_size                = 2
asg_max_size                = 6
asg_desired_capacity        = 2
